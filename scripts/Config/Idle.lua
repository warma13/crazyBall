-- ============================================================================
-- Config/Idle.lua - 放置模式配置
-- ============================================================================

local M = {}

M.IDLE = {
    BALL_COST_MULT      = 80,
    SLOT_COST_MULT      = 30,
    DRAW_COST_MULT      = 40,
    EFFECT_COST_MULT    = 25,
    DRAW_GEM_TO_COIN    = 500,
    BASE_DROP_VALUE     = 1,
    PRESTIGE_THRESHOLD  = "1000000000000",
    PRESTIGE_MULT_BONUS = 0.5,
    MAX_IDLE_SLOTS      = 5,
    IDLE_SLOT_INIT_LV   = 1,

    -- 关卡系统
    SLOT_UPGRADE_BASE_N     = 5,
    SLOT_UPGRADE_N_GROWTH   = 1.4,

    -- 关卡推进（球币门槛）
    LEVEL_THRESHOLD_BASE    = 1800,
    LEVEL_THRESHOLD_GROWTH  = 5.5,

    -- 双币种
    BALL_COIN_RATIO     = 1.0,
    GOLD_COIN_RATIO     = 0.2,

    -- ================================================================
    -- 全局升级系统（金币消费，永久生效，转生不重置）
    -- ================================================================
    -- 费用公式: baseCost * costGrowth ^ level
    -- 5个梯度: 1 → 3亿（9个数量级差距）
    UPGRADES = {
        -- ═══════════════════════════════════════════════
        -- Tier 1 · 基础 (baseCost 5~1000) — 即时~5min解锁
        -- ═══════════════════════════════════════════════
        {
            id          = "drop_cooldown",
            name        = "掉落加速",
            desc        = "缩短弹珠投放间隔",
            unlockLevel = 1,
            maxLevel    = 15,
            baseCost    = 5,
            costGrowth  = 2.2,
            baseCooldown = 3.5,
            cooldownK    = 0.15,
            minCooldown  = 0.5,
            formatValue = function(lv, cfg)
                local val = cfg.baseCooldown / (1 + cfg.cooldownK * lv)
                return string.format("%.1fs", math.max(cfg.minCooldown, val))
            end,
        },
        {
            id          = "base_value",
            name        = "基础价值",
            desc        = "提高每颗弹珠的基础收益",
            unlockLevel = 2,
            maxLevel    = 30,
            baseCost    = 50,
            costGrowth  = 2.0,
            perLevel    = 0.5,
            formatValue = function(lv, cfg)
                return tostring(1 + lv * cfg.perLevel)
            end,
        },
        {
            id          = "peg_gold",
            name        = "撞钉奖励",
            desc        = "弹珠每次撞到钉子获得金币",
            unlockLevel = 3,
            maxLevel    = 20,
            baseCost    = 1000,
            costGrowth  = 2.1,
            perLevel    = 0.5,
            formatValue = function(lv, cfg)
                local v = lv * cfg.perLevel
                if v == math.floor(v) then
                    return string.format("+%d/钉", v)
                else
                    return string.format("+%.1f/钉", v)
                end
            end,
        },
        -- ═══════════════════════════════════════════════
        -- Tier 2 · 进阶 (baseCost 3000~10000) — 10~30min解锁
        -- ═══════════════════════════════════════════════
        {
            id          = "coin_magnet",
            name        = "金币磁铁",
            desc        = "提高落袋时的金币收益",
            unlockLevel = 4,
            maxLevel    = 20,
            baseCost    = 3000,
            costGrowth  = 2.2,
            perLevel    = 0.03,
            formatValue = function(lv, cfg)
                return string.format("+%d%%", math.floor(lv * cfg.perLevel * 100))
            end,
        },

        {
            id          = "crit_chance",
            name        = "暴击概率",
            desc        = "落袋时触发暴击的概率",
            unlockLevel = 5,
            maxLevel    = 20,
            baseCost    = 10000,
            costGrowth  = 2.3,
            perLevel    = 1.5,
            formatValue = function(lv, cfg)
                return string.format("%d%%", lv * cfg.perLevel)
            end,
        },

        -- ═══════════════════════════════════════════════
        -- Tier 3 · 高级 (baseCost 30000~200000) — 1~4h解锁
        -- ═══════════════════════════════════════════════
        {
            id          = "slot_base",
            name        = "底袋强化",
            desc        = "提高新关卡底袋的初始等级",
            unlockLevel = 6,
            maxLevel    = 15,
            baseCost    = 30000,
            costGrowth  = 2.2,
            perLevel    = 1,
            formatValue = function(lv, cfg)
                return string.format("+%d", lv * cfg.perLevel)
            end,
        },
        {
            id          = "multi_drop",
            name        = "多重投放",
            desc        = "每次投放有概率额外掉一颗球",
            unlockLevel = 7,
            maxLevel    = 8,
            baseCost    = 80000,
            costGrowth  = 2.5,
            perLevel    = 0.06,
            formatValue = function(lv, cfg)
                return string.format("%d%%", math.floor(lv * cfg.perLevel * 100))
            end,
        },
        {
            id          = "crit_mult",
            name        = "暴击倍率",
            desc        = "暴击时的收益倍数",
            unlockLevel = 8,
            maxLevel    = 20,
            baseCost    = 200000,
            costGrowth  = 2.3,
            perLevel    = 0.12,
            formatValue = function(lv, cfg)
                return string.format("%.1fx", 2.0 + lv * cfg.perLevel)
            end,
        },

        -- ═══════════════════════════════════════════════
        -- Tier 4 · 精英 (baseCost 50万~1500万) — 6~24h解锁
        -- ═══════════════════════════════════════════════
        {
            id          = "extra_ball",
            name        = "额外弹珠",
            desc        = "每次投放同时多掉额外弹珠",
            unlockLevel = 9,
            maxLevel    = 5,
            baseCost    = 500000,
            costGrowth  = 3.0,
            perLevel    = 1,
            formatValue = function(lv, cfg)
                return string.format("+%d颗", lv * cfg.perLevel)
            end,
        },
        {
            id          = "sky_drop",
            name        = "天降弹珠",
            desc        = "自动从天上掉落免费弹珠",
            unlockLevel = 10,
            maxLevel    = 12,
            baseCost    = 1500000,
            costGrowth  = 2.4,
            baseInterval = 8.0,
            intervalK    = 0.12,
            minInterval  = 1.0,
            formatValue = function(lv, cfg)
                if lv == 0 then return "" end
                local val = cfg.baseInterval / (1 + cfg.intervalK * lv)
                return string.format("%.1fs/颗", math.max(cfg.minInterval, val))
            end,
        },
        {
            id          = "heavy_landing",
            name        = "重力落袋",
            desc        = "落袋收益额外提升一个倍率",
            unlockLevel = 11,
            maxLevel    = 20,
            baseCost    = 5000000,
            costGrowth  = 2.3,
            perLevel    = 0.04,      -- 每级落袋倍率+4%
            formatValue = function(lv, cfg)
                return string.format("+%d%%倍率", math.floor(lv * cfg.perLevel * 100))
            end,
        },
        {
            id          = "combo_storm",
            name        = "连击风暴",
            desc        = "短时间内连续落袋获得递增加成",
            unlockLevel = 13,
            maxLevel    = 15,
            baseCost    = 15000000,
            costGrowth  = 2.2,
            perLevel    = 0.03,      -- 每级连击加成+3%/次
            comboWindow  = 3.0,      -- 连击判定窗口(秒)
            formatValue = function(lv, cfg)
                if lv == 0 then return "" end
                return string.format("+%d%%/次 %.0fs窗口", math.floor(lv * cfg.perLevel * 100), cfg.comboWindow)
            end,
        },
        -- ═══════════════════════════════════════════════
        -- Tier 5 · 终极 (baseCost 5000万~8亿) — 3~10d解锁
        -- ═══════════════════════════════════════════════
        {
            id          = "slot_fortune",
            name        = "口袋祝福",
            desc        = "落袋有概率触发收益翻倍",
            unlockLevel = 16,
            maxLevel    = 12,
            baseCost    = 50000000,
            costGrowth  = 2.5,
            perLevel    = 0.03,      -- 每级3%概率口袋收益翻倍
            cap         = 0.40,
            baseMult    = 2,         -- 基础翻倍
            formatValue = function(lv, cfg)
                if lv == 0 then return "" end
                local v = math.min(cfg.cap, lv * cfg.perLevel)
                local m = cfg.baseMult + math.floor(lv / 6)
                return string.format("%d%%概率×%d", math.floor(v * 100), m)
            end,
        },
        {
            id          = "prestige_boost",
            name        = "转生加成",
            desc        = "提高每次转生的倍率加成",
            unlockLevel = 19,
            maxLevel    = 10,
            baseCost    = 200000000,
            costGrowth  = 2.4,
            perLevel    = 0.15,      -- 每级+15%转生倍率
            formatValue = function(lv, cfg)
                return string.format("+%d%%", math.floor(lv * cfg.perLevel * 100))
            end,
        },
        {
            id          = "earning_amp",
            name        = "收益放大",
            desc        = "所有收益的最终乘数加成",
            unlockLevel = 21,
            maxLevel    = 15,
            baseCost    = 800000000,
            costGrowth  = 2.3,
            perLevel    = 0.05,      -- 每级最终收益+5%
            formatValue = function(lv, cfg)
                return string.format("+%d%%", math.floor(lv * cfg.perLevel * 100))
            end,
        },
    },
}

-- ================================================================
-- 技能系统（三选一获取，重复升级，转生保留）
-- CD 主动技能：玩家手动点击触发，分 instant（立即生效）和 duration（持续 buff）两类
-- ================================================================
M.IDLE.SKILLS = {
    -- ─── instant 类：点击立即触发效果，然后进入 CD ───
    {
        id            = "mass_drop",
        name          = "大量掉落",
        desc          = "立即掉落大量弹珠",
        icon          = "雨",
        iconImage     = "image/skill_mass_drop_20260519070609.png",
        iconColor     = { 120, 200, 255 },
        maxLevel      = 5,
        skillType     = "instant",
        cooldown      = 25.0,        -- 基础CD
        cdPerLevel    = 2.0,         -- 每级减少CD
        minCooldown   = 10.0,
        baseBallCount = 10,
        ballCountPerLv = 5,
        formatValue   = function(lv, cfg)
            local cd = math.max(cfg.minCooldown, cfg.cooldown - (lv - 1) * cfg.cdPerLevel)
            local count = cfg.baseBallCount + (lv - 1) * cfg.ballCountPerLv
            return string.format("掉%d球 CD%.0fs", count, cd)
        end,
    },
    {
        id            = "ball_rain",
        name          = "弹珠雨",
        desc          = "瞬间投放一波额外弹珠",
        icon          = "珠",
        iconImage     = "image/skill_ball_rain_20260519070604.png",
        iconColor     = { 80, 160, 255 },
        maxLevel      = 5,
        skillType     = "instant",
        cooldown      = 20.0,
        cdPerLevel    = 2.0,
        minCooldown   = 8.0,
        baseBallCount = 5,
        ballCountPerLv = 3,
        formatValue   = function(lv, cfg)
            local cd = math.max(cfg.minCooldown, cfg.cooldown - (lv - 1) * cfg.cdPerLevel)
            local count = cfg.baseBallCount + (lv - 1) * cfg.ballCountPerLv
            return string.format("掉%d球 CD%.0fs", count, cd)
        end,
    },
    -- ─── instant 特效类：触发时产生壮观的视觉效果 ───
    {
        id            = "giant_ball",
        name          = "巨型弹珠",
        desc          = "投放一颗超大弹珠，碾压一切钉子",
        icon          = "巨",
        iconImage     = "image/skill_giant_ball_20260519070559.png",
        iconColor     = { 255, 180, 50 },
        maxLevel      = 5,
        skillType     = "instant",
        cooldown      = 30.0,
        cdPerLevel    = 2.5,
        minCooldown   = 12.0,
        baseSize      = 3.0,       -- 基础大小倍率
        sizePerLv     = 0.5,       -- 每级增加倍率
        baseValueMult = 5,         -- 基础价值倍率
        valueMultPerLv = 2,        -- 每级价值倍率增加
        formatValue   = function(lv, cfg)
            local cd = math.max(cfg.minCooldown, cfg.cooldown - (lv - 1) * cfg.cdPerLevel)
            local size = cfg.baseSize + (lv - 1) * cfg.sizePerLv
            local valM = cfg.baseValueMult + (lv - 1) * cfg.valueMultPerLv
            return string.format("%.0fx大 %dx价值 CD%.0fs", size, valM, cd)
        end,
    },
    {
        id            = "fireworks",
        name          = "烟花爆破",
        desc          = "在棋盘上爆出一团弹珠烟花",
        icon          = "焰",
        iconImage     = "image/skill_firework_20260519070559.png",
        iconColor     = { 255, 100, 60 },
        maxLevel      = 5,
        skillType     = "instant",
        cooldown      = 28.0,
        cdPerLevel    = 2.0,
        minCooldown   = 12.0,
        baseWaves     = 2,          -- 基础波数
        wavesPerLv    = 1,          -- 每级增加波数
        ballsPerWave  = 6,          -- 每波球数
        formatValue   = function(lv, cfg)
            local cd = math.max(cfg.minCooldown, cfg.cooldown - (lv - 1) * cfg.cdPerLevel)
            local waves = cfg.baseWaves + (lv - 1) * cfg.wavesPerLv
            local total = waves * cfg.ballsPerWave
            return string.format("%d波%d球 CD%.0fs", waves, total, cd)
        end,
    },
    {
        id            = "golden_shower",
        name          = "黄金雨",
        desc          = "从天上降下一排金色高价值弹珠",
        icon          = "金",
        iconImage     = "image/skill_golden_rain_20260519070559.png",
        iconColor     = { 255, 220, 60 },
        maxLevel      = 5,
        skillType     = "instant",
        cooldown      = 32.0,
        cdPerLevel    = 2.5,
        minCooldown   = 14.0,
        baseBallCount = 8,
        ballCountPerLv = 3,
        baseValueMult = 3,         -- 金色球价值倍率
        valueMultPerLv = 1,
        formatValue   = function(lv, cfg)
            local cd = math.max(cfg.minCooldown, cfg.cooldown - (lv - 1) * cfg.cdPerLevel)
            local count = cfg.baseBallCount + (lv - 1) * cfg.ballCountPerLv
            local valM = cfg.baseValueMult + (lv - 1) * cfg.valueMultPerLv
            return string.format("%d金球 %dx价值 CD%.0fs", count, valM, cd)
        end,
    },
    {
        id            = "peg_explosion",
        name          = "钉阵爆破",
        desc          = "所有钉子同时爆炸产出大量金币",
        icon          = "爆",
        iconImage     = "image/skill_peg_explode_20260519070611.png",
        iconColor     = { 255, 60, 60 },
        maxLevel      = 5,
        skillType     = "instant",
        cooldown      = 35.0,
        cdPerLevel    = 3.0,
        minCooldown   = 15.0,
        baseGoldPerPeg = 5,         -- 每钉基础金币
        goldPerPegPerLv = 3,        -- 每级每钉增加
        formatValue   = function(lv, cfg)
            local cd = math.max(cfg.minCooldown, cfg.cooldown - (lv - 1) * cfg.cdPerLevel)
            local gold = cfg.baseGoldPerPeg + (lv - 1) * cfg.goldPerPegPerLv
            return string.format("每钉%d金 CD%.0fs", gold, cd)
        end,
    },
    {
        id            = "split_burst",
        name          = "分裂风暴",
        desc          = "持续一段时间，每隔一段时间场上弹珠自动分裂",
        icon          = "裂",
        iconImage     = "image/skill_split_storm_20260519070559.png",
        iconColor     = { 100, 200, 255 },
        maxLevel      = 5,
        skillType     = "duration",
        cooldown      = 25.0,
        cdPerLevel    = 2.0,
        minCooldown   = 10.0,
        baseDuration  = 6.0,       -- 基础持续时间（秒）
        durationPerLv = 1.5,       -- 每级增加持续时间
        splitInterval = 2.0,       -- 每隔多少秒分裂一波
        baseSplitCount = 2,        -- 每球分裂出几颗
        splitPerLv    = 1,         -- 每级增加分裂数
        formatValue   = function(lv, cfg)
            local cd = math.max(cfg.minCooldown, cfg.cooldown - (lv - 1) * cfg.cdPerLevel)
            local dur = cfg.baseDuration + (lv - 1) * cfg.durationPerLv
            local splits = cfg.baseSplitCount + (lv - 1) * cfg.splitPerLv
            return string.format("持续%.0fs 每球裂%d颗 CD%.0fs", dur, splits, cd)
        end,
    },
    {
        id            = "slot_jackpot",
        name          = "底袋狂欢",
        desc          = "所有底袋同时喷出大量金币奖励",
        icon          = "奖",
        iconImage     = "image/skill_slot_party_20260519070558.png",
        iconColor     = { 255, 200, 100 },
        maxLevel      = 5,
        skillType     = "instant",
        cooldown      = 35.0,
        cdPerLevel    = 3.0,
        minCooldown   = 15.0,
        baseMultPerSlot = 10,      -- 每个底袋基础倍率
        multPerSlotPerLv = 5,      -- 每级每底袋增加倍率
        formatValue   = function(lv, cfg)
            local cd = math.max(cfg.minCooldown, cfg.cooldown - (lv - 1) * cfg.cdPerLevel)
            local m = cfg.baseMultPerSlot + (lv - 1) * cfg.multPerSlotPerLv
            return string.format("每袋%dx奖 CD%.0fs", m, cd)
        end,
    },
}

-- ================================================================
-- 弹珠能力升级（球币消费，每关弹珠独立，转生不重置）
-- ================================================================
-- unlockReq: 前一个升级需达到的等级才能解锁本项（第1项无需前置）
-- goalLevel: 本项需达到的等级才算"通关"，所有项达成 goalLevel 后解锁下一关
-- BALL_UPGRADES_BY_TYPE: 以球 effect.id 为 key, 每种球独立升级列表

-- ── 通用升级模板（供各球类型复用） ──
local _autoDropTemplate = function(baseCost)
    return {
        id          = "ball_auto_drop",
        name        = "自动掉落",
        desc        = "自动投放弹珠",
        maxLevel    = 15,
        baseCost    = baseCost or 20,
        costGrowth  = 2.2,
        unlockReq   = 0,
        goalLevel   = 3,
        baseInterval = 5.0,
        intervalK    = 0.18,
        minInterval  = 0.8,
        formatValue = function(lv, cfg)
            if lv == 0 then return "" end
            local val = cfg.baseInterval / (1 + cfg.intervalK * lv)
            return string.format("%.1fs/颗", math.max(cfg.minInterval, val))
        end,
    }
end

local _baseValueTemplate = function(baseCost, unlockReq, goalLevel)
    return {
        id          = "ball_base_value",
        name        = "基础价值",
        desc        = "提高弹珠落袋收益",
        maxLevel    = 25,
        baseCost    = baseCost or 300,
        costGrowth  = 2.0,
        unlockReq   = unlockReq or 3,
        goalLevel   = goalLevel or 5,
        perLevel    = 0.5,
        formatValue = function(lv, cfg)
            local v = lv * cfg.perLevel
            if v == math.floor(v) then
                return string.format("+%d", v)
            else
                return string.format("+%.1f", v)
            end
        end,
    }
end

M.BALL_UPGRADES_BY_TYPE = {
    -- ══════════════════════════════════════
    -- 1. 铁球 (sturdy) - 撞钉越多价值越高
    -- ══════════════════════════════════════
    sturdy = {
        _autoDropTemplate(20),
        _baseValueTemplate(300, 3, 5),
        {
            id          = "sturdy_peg_value",
            name        = "坚韧撞击",
            desc        = "降低撞钉递增门槛(更快触发加成)",
            maxLevel    = 15,
            baseCost    = 1000,
            costGrowth  = 2.2,
            unlockReq   = 5,
            goalLevel   = 3,
            perLevel    = 1,       -- 每级门槛-1钉
            formatValue = function(lv, cfg)
                local base = 5
                return string.format("每%d钉触发", math.max(1, base - lv * cfg.perLevel))
            end,
        },
        {
            id          = "sturdy_bonus_pct",
            name        = "硬化强度",
            desc        = "提高撞钉触发时的加成比例",
            maxLevel    = 12,
            baseCost    = 5000,
            costGrowth  = 2.3,
            unlockReq   = 3,
            goalLevel   = 2,
            perLevel    = 0.03,    -- 每级+3%加成
            formatValue = function(lv, cfg)
                local base = 0.10
                return string.format("+%d%%/次", math.floor((base + lv * cfg.perLevel) * 100))
            end,
        },
        {
            id          = "sturdy_endurance",
            name        = "持久锻造",
            desc        = "落袋收益乘数提升",
            maxLevel    = 10,
            baseCost    = 50000,
            costGrowth  = 2.3,
            unlockReq   = 2,
            goalLevel   = 1,
            perLevel    = 0.10,
            formatValue = function(lv, cfg)
                return string.format("x%.2f", 1.0 + lv * cfg.perLevel)
            end,
        },
    },

    -- ══════════════════════════════════════
    -- 2. 铜球 (bouncy) - 弹跳衰减更小
    -- ══════════════════════════════════════
    bouncy = {
        _autoDropTemplate(20),
        _baseValueTemplate(300, 3, 5),
        {
            id          = "bouncy_elasticity",
            name        = "超级弹力",
            desc        = "提高弹跳恢复系数",
            maxLevel    = 15,
            baseCost    = 1000,
            costGrowth  = 2.2,
            unlockReq   = 5,
            goalLevel   = 3,
            perLevel    = 0.02,
            cap         = 0.35,
            formatValue = function(lv, cfg)
                local v = math.min(cfg.cap, lv * cfg.perLevel)
                return string.format("+%d%%弹力", math.floor(v * 100))
            end,
        },
        {
            id          = "bouncy_peg_bonus",
            name        = "弹射奖励",
            desc        = "每次撞钉概率获得额外球币",
            maxLevel    = 12,
            baseCost    = 5000,
            costGrowth  = 2.3,
            unlockReq   = 3,
            goalLevel   = 2,
            perLevel    = 0.04,
            formatValue = function(lv, cfg)
                return string.format("%d%%概率+球币", math.floor(lv * cfg.perLevel * 100))
            end,
        },
        {
            id          = "bouncy_damping",
            name        = "衰减抑制",
            desc        = "减少弹跳衰减损失",
            maxLevel    = 10,
            baseCost    = 50000,
            costGrowth  = 2.3,
            unlockReq   = 2,
            goalLevel   = 1,
            perLevel    = 0.03,
            formatValue = function(lv, cfg)
                return string.format("衰减-%d%%", math.floor(lv * cfg.perLevel * 100))
            end,
        },
    },

    -- ══════════════════════════════════════
    -- 3. 银球 (split) - 分裂
    -- ══════════════════════════════════════
    split = {
        _autoDropTemplate(20),
        _baseValueTemplate(300, 3, 5),
        {
            id          = "split_threshold",
            name        = "快速分裂",
            desc        = "降低分裂触发所需撞钉次数",
            maxLevel    = 12,
            baseCost    = 1200,
            costGrowth  = 2.2,
            unlockReq   = 5,
            goalLevel   = 3,
            perLevel    = 1,
            formatValue = function(lv, cfg)
                local base = 5
                return string.format("每%d钉分裂", math.max(2, base - lv * cfg.perLevel))
            end,
        },
        {
            id          = "split_value",
            name        = "分裂增值",
            desc        = "分裂球继承更高价值比例",
            maxLevel    = 12,
            baseCost    = 6000,
            costGrowth  = 2.3,
            unlockReq   = 3,
            goalLevel   = 2,
            perLevel    = 0.08,
            formatValue = function(lv, cfg)
                return string.format("继承%d%%价值", math.floor((0.5 + lv * cfg.perLevel) * 100))
            end,
        },
        {
            id          = "split_count",
            name        = "多重分裂",
            desc        = "每次分裂产生更多球",
            maxLevel    = 5,
            baseCost    = 80000,
            costGrowth  = 2.5,
            unlockReq   = 2,
            goalLevel   = 1,
            perLevel    = 1,
            formatValue = function(lv, cfg)
                return string.format("分裂%d颗", 1 + lv * cfg.perLevel)
            end,
        },
    },

    -- ══════════════════════════════════════
    -- 4. 水晶球 (pierce) - 穿透不减速
    -- ══════════════════════════════════════
    pierce = {
        _autoDropTemplate(20),
        _baseValueTemplate(300, 3, 5),
        {
            id          = "pierce_speed",
            name        = "穿透加速",
            desc        = "穿透撞钉时获得速度加成",
            maxLevel    = 15,
            baseCost    = 1500,
            costGrowth  = 2.2,
            unlockReq   = 5,
            goalLevel   = 3,
            perLevel    = 0.05,
            formatValue = function(lv, cfg)
                return string.format("+%d%%速度", math.floor(lv * cfg.perLevel * 100))
            end,
        },
        {
            id          = "pierce_chain",
            name        = "连穿奖励",
            desc        = "连续穿透钉子时收益递增",
            maxLevel    = 12,
            baseCost    = 8000,
            costGrowth  = 2.3,
            unlockReq   = 3,
            goalLevel   = 2,
            perLevel    = 0.03,
            formatValue = function(lv, cfg)
                return string.format("+%d%%/钉", math.floor(lv * cfg.perLevel * 100))
            end,
        },
        {
            id          = "pierce_crit",
            name        = "透晶暴击",
            desc        = "穿透钉数越多暴击概率越高",
            maxLevel    = 10,
            baseCost    = 100000,
            costGrowth  = 2.3,
            unlockReq   = 2,
            goalLevel   = 1,
            perLevel    = 0.5,
            formatValue = function(lv, cfg)
                return string.format("+%.1f%%/钉", lv * cfg.perLevel)
            end,
        },
    },

    -- ══════════════════════════════════════
    -- 5. 金球 (midas) - 撞钉+金币+宝石
    -- ══════════════════════════════════════
    midas = {
        _autoDropTemplate(20),
        _baseValueTemplate(300, 3, 5),
        {
            id          = "midas_peg_gold",
            name        = "点金强化",
            desc        = "提高每次撞钉的金币奖励",
            maxLevel    = 15,
            baseCost    = 2000,
            costGrowth  = 2.2,
            unlockReq   = 5,
            goalLevel   = 3,
            perLevel    = 1,
            formatValue = function(lv, cfg)
                local base = 3
                return string.format("+%d金币/钉", base + lv * cfg.perLevel)
            end,
        },
        {
            id          = "midas_gem_chance",
            name        = "宝石精通",
            desc        = "提高撞钉产出宝石的概率",
            maxLevel    = 12,
            baseCost    = 10000,
            costGrowth  = 2.3,
            unlockReq   = 3,
            goalLevel   = 2,
            perLevel    = 0.02,
            formatValue = function(lv, cfg)
                local base = 0.05
                return string.format("%d%%产宝石", math.floor((base + lv * cfg.perLevel) * 100))
            end,
        },
        {
            id          = "midas_touch",
            name        = "黄金之触",
            desc        = "落袋收益倍率提升",
            maxLevel    = 10,
            baseCost    = 120000,
            costGrowth  = 2.3,
            unlockReq   = 2,
            goalLevel   = 1,
            perLevel    = 0.12,
            formatValue = function(lv, cfg)
                return string.format("x%.2f", 1.0 + lv * cfg.perLevel)
            end,
        },
    },

    -- ══════════════════════════════════════
    -- 6. 钻石球 (crit) - 暴击双倍
    -- ══════════════════════════════════════
    crit = {
        _autoDropTemplate(20),
        _baseValueTemplate(300, 3, 5),
        {
            id          = "crit_chance_up",
            name        = "暴击精通",
            desc        = "提高暴击触发概率",
            maxLevel    = 15,
            baseCost    = 2500,
            costGrowth  = 2.2,
            unlockReq   = 5,
            goalLevel   = 3,
            perLevel    = 1.5,
            formatValue = function(lv, cfg)
                return string.format("+%.1f%%暴击", lv * cfg.perLevel)
            end,
        },
        {
            id          = "crit_damage",
            name        = "暴击威力",
            desc        = "暴击时的倍率更高",
            maxLevel    = 12,
            baseCost    = 12000,
            costGrowth  = 2.3,
            unlockReq   = 3,
            goalLevel   = 2,
            perLevel    = 0.15,
            formatValue = function(lv, cfg)
                return string.format("暴击x%.1f", 2.0 + lv * cfg.perLevel)
            end,
        },
        {
            id          = "crit_streak",
            name        = "连暴加成",
            desc        = "连续暴击时额外加成",
            maxLevel    = 10,
            baseCost    = 150000,
            costGrowth  = 2.3,
            unlockReq   = 2,
            goalLevel   = 1,
            perLevel    = 0.10,
            formatValue = function(lv, cfg)
                return string.format("+%d%%/连暴", math.floor(lv * cfg.perLevel * 100))
            end,
        },
    },

    -- ══════════════════════════════════════
    -- 7. 红宝石球 (blaze) - 撞钉+金币
    -- ══════════════════════════════════════
    blaze = {
        _autoDropTemplate(20),
        _baseValueTemplate(300, 3, 5),
        {
            id          = "blaze_peg_gold",
            name        = "灼烧强化",
            desc        = "提高每次撞钉的金币奖励",
            maxLevel    = 15,
            baseCost    = 3000,
            costGrowth  = 2.2,
            unlockReq   = 5,
            goalLevel   = 3,
            perLevel    = 2,
            formatValue = function(lv, cfg)
                local base = 5
                return string.format("+%d金币/钉", base + lv * cfg.perLevel)
            end,
        },
        {
            id          = "blaze_burn",
            name        = "余烬燃烧",
            desc        = "撞钉后该钉子短时间内再被撞有额外奖励",
            maxLevel    = 12,
            baseCost    = 15000,
            costGrowth  = 2.3,
            unlockReq   = 3,
            goalLevel   = 2,
            perLevel    = 0.15,
            formatValue = function(lv, cfg)
                return string.format("+%d%%余烬奖励", math.floor(lv * cfg.perLevel * 100))
            end,
        },
        {
            id          = "blaze_multiplier",
            name        = "烈焰倍率",
            desc        = "落袋收益乘数提升",
            maxLevel    = 10,
            baseCost    = 180000,
            costGrowth  = 2.3,
            unlockReq   = 2,
            goalLevel   = 1,
            perLevel    = 0.10,
            formatValue = function(lv, cfg)
                return string.format("x%.2f", 1.0 + lv * cfg.perLevel)
            end,
        },
    },

    -- ══════════════════════════════════════
    -- 8. 翡翠球 (fortune) - 落袋额外奖金
    -- ══════════════════════════════════════
    fortune = {
        _autoDropTemplate(20),
        _baseValueTemplate(300, 3, 5),
        {
            id          = "fortune_bonus",
            name        = "聚财强化",
            desc        = "提高落袋额外奖金比例",
            maxLevel    = 15,
            baseCost    = 3500,
            costGrowth  = 2.2,
            unlockReq   = 5,
            goalLevel   = 3,
            perLevel    = 0.05,
            formatValue = function(lv, cfg)
                local base = 0.25
                return string.format("+%d%%奖金", math.floor((base + lv * cfg.perLevel) * 100))
            end,
        },
        {
            id          = "fortune_luck",
            name        = "幸运翡翠",
            desc        = "落袋有概率双倍奖金",
            maxLevel    = 12,
            baseCost    = 18000,
            costGrowth  = 2.3,
            unlockReq   = 3,
            goalLevel   = 2,
            perLevel    = 0.03,
            formatValue = function(lv, cfg)
                return string.format("%d%%双倍", math.floor(lv * cfg.perLevel * 100))
            end,
        },
        {
            id          = "fortune_jackpot",
            name        = "翡翠宝箱",
            desc        = "稀有概率触发超大奖金",
            maxLevel    = 8,
            baseCost    = 200000,
            costGrowth  = 2.5,
            unlockReq   = 2,
            goalLevel   = 1,
            perLevel    = 0.01,
            jackpotMult = 10,
            formatValue = function(lv, cfg)
                return string.format("%d%%概率x%d", math.floor(lv * cfg.perLevel * 100), cfg.jackpotMult)
            end,
        },
    },

    -- ══════════════════════════════════════
    -- 9. 陨石球 (impact) - 重力+落袋倍率
    -- ══════════════════════════════════════
    impact = {
        _autoDropTemplate(20),
        _baseValueTemplate(300, 3, 5),
        {
            id          = "impact_gravity",
            name        = "重力强化",
            desc        = "增加下落加速度",
            maxLevel    = 15,
            baseCost    = 4000,
            costGrowth  = 2.2,
            unlockReq   = 5,
            goalLevel   = 3,
            perLevel    = 0.08,
            formatValue = function(lv, cfg)
                local base = 0.30
                return string.format("+%d%%重力", math.floor((base + lv * cfg.perLevel) * 100))
            end,
        },
        {
            id          = "impact_landing",
            name        = "冲击落袋",
            desc        = "提高落袋收益倍率",
            maxLevel    = 12,
            baseCost    = 20000,
            costGrowth  = 2.3,
            unlockReq   = 3,
            goalLevel   = 2,
            perLevel    = 0.08,
            formatValue = function(lv, cfg)
                local base = 0.35
                return string.format("+%d%%落袋倍率", math.floor((base + lv * cfg.perLevel) * 100))
            end,
        },
        {
            id          = "impact_shockwave",
            name        = "冲击波",
            desc        = "落袋时概率触发冲击波奖励",
            maxLevel    = 8,
            baseCost    = 250000,
            costGrowth  = 2.5,
            unlockReq   = 2,
            goalLevel   = 1,
            perLevel    = 0.04,
            formatValue = function(lv, cfg)
                return string.format("%d%%触发", math.floor(lv * cfg.perLevel * 100))
            end,
        },
    },

    -- ══════════════════════════════════════
    -- 10. 蓝宝石球 (combo_master) - 连击加成
    -- ══════════════════════════════════════
    combo_master = {
        _autoDropTemplate(20),
        _baseValueTemplate(300, 3, 5),
        {
            id          = "combo_amp",
            name        = "连击强化",
            desc        = "提高连击加成倍数",
            maxLevel    = 15,
            baseCost    = 5000,
            costGrowth  = 2.2,
            unlockReq   = 5,
            goalLevel   = 3,
            perLevel    = 0.20,
            formatValue = function(lv, cfg)
                local base = 2.0
                return string.format("连击x%.1f", base + lv * cfg.perLevel)
            end,
        },
        {
            id          = "combo_window",
            name        = "连击窗口",
            desc        = "延长连击判定时间",
            maxLevel    = 12,
            baseCost    = 25000,
            costGrowth  = 2.3,
            unlockReq   = 3,
            goalLevel   = 2,
            perLevel    = 0.3,
            formatValue = function(lv, cfg)
                local base = 2
                return string.format("+%.1fs窗口", base + lv * cfg.perLevel)
            end,
        },
        {
            id          = "combo_finisher",
            name        = "连击终结",
            desc        = "连击达到一定次数后触发额外大奖",
            maxLevel    = 8,
            baseCost    = 300000,
            costGrowth  = 2.5,
            unlockReq   = 2,
            goalLevel   = 1,
            perLevel    = 0.15,
            comboReq    = 5,
            formatValue = function(lv, cfg)
                return string.format("%d连击+%d%%奖励", cfg.comboReq, math.floor(lv * cfg.perLevel * 100))
            end,
        },
    },

    -- ══════════════════════════════════════
    -- 11. 珍珠球 (slot_master) - 不同口袋加成
    -- ══════════════════════════════════════
    slot_master = {
        _autoDropTemplate(20),
        _baseValueTemplate(300, 3, 5),
        {
            id          = "slot_diversity",
            name        = "口袋探索",
            desc        = "提高落入不同口袋的加成比例",
            maxLevel    = 15,
            baseCost    = 6000,
            costGrowth  = 2.2,
            unlockReq   = 5,
            goalLevel   = 3,
            perLevel    = 0.04,
            formatValue = function(lv, cfg)
                local base = 0.18
                return string.format("+%d%%/种", math.floor((base + lv * cfg.perLevel) * 100))
            end,
        },
        {
            id          = "slot_complete",
            name        = "全袋奖励",
            desc        = "落遍所有口袋后获得额外大奖",
            maxLevel    = 12,
            baseCost    = 30000,
            costGrowth  = 2.3,
            unlockReq   = 3,
            goalLevel   = 2,
            perLevel    = 0.20,
            formatValue = function(lv, cfg)
                return string.format("全袋+%d%%", math.floor(lv * cfg.perLevel * 100))
            end,
        },
        {
            id          = "slot_favorite",
            name        = "幸运口袋",
            desc        = "随机一个口袋成为幸运口袋,收益翻倍",
            maxLevel    = 8,
            baseCost    = 350000,
            costGrowth  = 2.5,
            unlockReq   = 2,
            goalLevel   = 1,
            perLevel    = 0.20,
            formatValue = function(lv, cfg)
                return string.format("幸运口袋x%.1f", 2.0 + lv * cfg.perLevel)
            end,
        },
    },

    -- ══════════════════════════════════════
    -- 12. 黑曜石球 (charge) - 蓄能释放
    -- ══════════════════════════════════════
    charge = {
        _autoDropTemplate(20),
        _baseValueTemplate(300, 3, 5),
        {
            id          = "charge_power",
            name        = "蓄能强化",
            desc        = "提高蓄能公式的指数",
            maxLevel    = 12,
            baseCost    = 7000,
            costGrowth  = 2.2,
            unlockReq   = 5,
            goalLevel   = 3,
            perLevel    = 0.1,
            formatValue = function(lv, cfg)
                local base = 2
                return string.format("指数: %.1f", base + lv * cfg.perLevel)
            end,
        },
        {
            id          = "charge_efficiency",
            name        = "蓄能效率",
            desc        = "每次撞钉蓄能量增加",
            maxLevel    = 12,
            baseCost    = 35000,
            costGrowth  = 2.3,
            unlockReq   = 3,
            goalLevel   = 2,
            perLevel    = 0.10,
            formatValue = function(lv, cfg)
                return string.format("+%d%%蓄能", math.floor(lv * cfg.perLevel * 100))
            end,
        },
        {
            id          = "charge_overload",
            name        = "能量过载",
            desc        = "蓄能满时释放额外爆发伤害",
            maxLevel    = 8,
            baseCost    = 400000,
            costGrowth  = 2.5,
            unlockReq   = 2,
            goalLevel   = 1,
            perLevel    = 0.25,
            formatValue = function(lv, cfg)
                return string.format("+%d%%爆发", math.floor(lv * cfg.perLevel * 100))
            end,
        },
    },

    -- ══════════════════════════════════════
    -- 13. 琥珀球 (tempo) - 速度→奖励
    -- ══════════════════════════════════════
    tempo = {
        _autoDropTemplate(20),
        _baseValueTemplate(300, 3, 5),
        {
            id          = "tempo_accel",
            name        = "节律加速",
            desc        = "加快速度增长",
            maxLevel    = 15,
            baseCost    = 8000,
            costGrowth  = 2.2,
            unlockReq   = 5,
            goalLevel   = 3,
            perLevel    = 0.01,
            formatValue = function(lv, cfg)
                local base = 0.04
                return string.format("加速率+%d%%", math.floor((base + lv * cfg.perLevel) * 100))
            end,
        },
        {
            id          = "tempo_reward",
            name        = "速度奖励",
            desc        = "提高速度与奖励的挂钩比例",
            maxLevel    = 12,
            baseCost    = 40000,
            costGrowth  = 2.3,
            unlockReq   = 3,
            goalLevel   = 2,
            perLevel    = 0.08,
            formatValue = function(lv, cfg)
                local base = 0.6
                return string.format("速度系数%.1f", base + lv * cfg.perLevel)
            end,
        },
        {
            id          = "tempo_frenzy",
            name        = "节律狂热",
            desc        = "速度达到阈值后触发狂热加成",
            maxLevel    = 8,
            baseCost    = 500000,
            costGrowth  = 2.5,
            unlockReq   = 2,
            goalLevel   = 1,
            perLevel    = 0.15,
            formatValue = function(lv, cfg)
                return string.format("狂热+%d%%", math.floor(lv * cfg.perLevel * 100))
            end,
        },
    },
}

--- 根据球效果ID获取该球的升级列表
---@param effectId string 球的 effect.id（如 "sturdy", "bouncy" 等）
---@return table[] 升级配置列表
function M.GetBallUpgradesForType(effectId)
    return M.BALL_UPGRADES_BY_TYPE[effectId] or M.BALL_UPGRADES_BY_TYPE["sturdy"]
end

-- 兼容旧接口：BALL_UPGRADES 指向铁球（默认）
M.BALL_UPGRADES = M.BALL_UPGRADES_BY_TYPE["sturdy"]

--- 获取升级费用（BigNum）
---@param upgCfg table 升级配置项
---@param currentLevel number 当前等级
---@return number
function M.GetUpgradeCost(upgCfg, currentLevel)
    if currentLevel >= upgCfg.maxLevel then return math.huge end
    return math.ceil(upgCfg.baseCost * (upgCfg.costGrowth ^ currentLevel))
end

return M
