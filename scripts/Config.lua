-- ============================================================================
-- Config.lua - 所有配置常量
-- ============================================================================

local BigNum = require("BigNum")

local M = {}

-- 弹珠台布局与物理
M.CONFIG = {
    Title = "疯狂弹珠",

    BOARD_MARGIN_TOP = 60,
    BOARD_SPLIT_RATIO = 0.52,
    BOARD_PADDING_X = 0,

    PEG_ROWS = 9,
    PEG_RADIUS = 4,
    PEG_COLOR = { 180, 200, 220, 255 },
    PEG_HIT_COLOR = { 255, 220, 100, 255 },
    PEG_HIT_DURATION = 0.3,

    GRAVITY = 600,
    BOUNCE_DAMPING = 0.6,
    BALL_RADIUS = 4.5,

    MAX_BALLS = 50,
    RANDOM_NUDGE = 40,

    MAX_SLOTS = 10,
    SLOT_HEIGHT = 40,

    DIVIDER_WIDTH = 3,
    DIVIDER_HEIGHT = 50,
    DIVIDER_COLOR = { 140, 160, 200, 230 },
    DIVIDER_GLOW_COLOR = { 180, 200, 240, 80 },

    POPUP_DURATION = 1.2,
    POPUP_RISE = 50,
}

-- 好坑倍率池
M.GOOD_MULT_POOL = { 1, 1, 2, 2, 3, 5, 10 }

-- 口袋倍率：无限升级，等级 N 对应倍率 = floor(1.3^(N-1))，至少为 N
--- 计算口袋等级对应的倍率
---@param level number 口袋等级（>=1）
---@return number 倍率值
function M.GetSlotMult(level)
    if level <= 1 then return 1 end
    return math.max(level, math.floor(1.3 ^ (level - 1)))
end

--- 计算口袋升级费用（从当前等级升到下一级）
--- 平滑增长：基础40, 增长率1.6（返回 BigNum 防溢出）
---@param level number 当前等级（>=1）
---@return table BigNum 升级费用
function M.GetSlotUpgradeCost(level)
    return math.floor(BigNum.new(40) * BigNum.new(1.6) ^ (level - 1))
end

local multColorCache = {}
local MULT_COLOR_1 = { 100, 115, 140, 255 }
--- 根据倍率值生成颜色（连续渐变，支持任意倍率）
--- 结果按 mult 缓存，避免每帧重复 math.log/sin 计算
---@param mult number
---@return table {r,g,b,a}
function M.GetMultColor(mult)
    if mult <= 1 then return MULT_COLOR_1 end
    local cached = multColorCache[mult]
    if cached then return cached end
    -- 使用 log 映射到色环
    local t = math.log(mult) / math.log(2)  -- log2(mult)
    local phase = t * 0.8  -- 色相旋转速度
    local r = math.floor(128 + 127 * math.sin(phase))
    local g = math.floor(128 + 127 * math.sin(phase + 2.094))  -- +120°
    local b = math.floor(128 + 127 * math.sin(phase + 4.189))  -- +240°
    -- 高倍率提高亮度
    local bright = math.min(1.3, 1.0 + t * 0.02)
    r = math.min(255, math.floor(r * bright))
    g = math.min(255, math.floor(g * bright))
    b = math.min(255, math.floor(b * bright))
    local color = { r, g, b, 255 }
    multColorCache[mult] = color
    return color
end

-- 解锁新坑位费用（10个口袋默认全部解锁，无需额外解锁）
M.SLOT_UNLOCK_COSTS = {}

-- 钢珠类型（baseValue约×3~4递增，cost平滑递增）
M.BALL_TYPES = {
    {
        name = "铁球", baseValue = 2, cost = 0,
        color = { 160, 170, 180, 255 },
        glowColor = { 200, 210, 220, 120 },
        skinKey = "iron",
        effect = { id = "sturdy", name = "坚韧", desc = "撞钉越多价值越高,每撞5钉+10%球价值", hitScale = 5, bonusPct = 0.10 },
    },
    {
        name = "铜球", baseValue = 6, cost = 500,
        color = { 205, 133, 63, 255 },
        glowColor = { 230, 170, 100, 120 },
        skinKey = "copper",
        effect = { id = "bouncy", name = "弹力", desc = "弹跳衰减更小，撞更多钉", damping = 0.78 },
    },
    {
        name = "银球", baseValue = 18, cost = 15000,
        color = { 200, 210, 225, 255 },
        glowColor = { 230, 240, 255, 140 },
        skinKey = "silver",
        effect = { id = "split", name = "分裂", desc = "撞5次钉后分裂出1颗免费球", hitThreshold = 5 },
    },
    {
        name = "水晶球", baseValue = 50, cost = 500000,
        color = { 180, 220, 255, 255 },
        glowColor = { 200, 235, 255, 160 },
        skinKey = "crystal",
        effect = { id = "pierce", name = "穿透", desc = "撞钉不减速,保持高速撞更多钉", keepSpeed = true },
    },
    {
        name = "金球", baseValue = 150, cost = 20000000,
        adOnly = true,
        color = { 255, 215, 0, 255 },
        glowColor = { 255, 240, 100, 160 },
        skinKey = "gold",
        effect = { id = "midas", name = "点金", desc = "每次撞钉 +3 金币,5%概率产出宝石", pegBonus = 3, gemChance = 0.05 },
    },
    {
        name = "钻石球", baseValue = 500, cost = 1000000000,
        color = { 100, 230, 255, 255 },
        glowColor = { 150, 240, 255, 180 },
        skinKey = "diamond",
        effect = { id = "crit", name = "暴击", desc = "20%概率双倍落袋奖励", chance = 0.20 },
    },
    {
        name = "红宝石球", baseValue = 1800, cost = 50000000000,
        color = { 230, 50, 80, 255 },
        glowColor = { 255, 100, 120, 180 },
        skinKey = "ruby",
        effect = { id = "blaze", name = "灼烧", desc = "每次撞钉 +5 金币", pegBonus = 5 },
    },
    {
        name = "翡翠球", baseValue = 6000, cost = 3000000000000,
        color = { 50, 210, 120, 255 },
        glowColor = { 100, 240, 160, 160 },
        skinKey = "jade",
        effect = { id = "fortune", name = "聚财", desc = "落袋额外+25%基础价值奖金", bonusRatio = 0.25 },
    },
    {
        name = "陨石球", baseValue = 20000, cost = 300000000000000,
        color = { 200, 100, 40, 255 },
        glowColor = { 255, 150, 60, 200 },
        skinKey = "meteor",
        effect = { id = "impact", name = "冲击", desc = "+30%重力，+35%落袋倍率", gravityMult = 1.3, multBonus = 0.35 },
    },
    {
        name = "蓝宝石球", baseValue = 70000, cost = 30000000000000000,
        color = { 40, 80, 220, 255 },
        glowColor = { 80, 120, 255, 180 },
        skinKey = "sapphire",
        effect = { id = "combo_master", name = "连击宗师", desc = "连击加成翻倍,连击窗口+2s", comboAmp = 2.0, windowBonus = 2 },
    },
    {
        name = "珍珠球", baseValue = 250000, cost = 5000000000000000000,
        color = { 240, 230, 220, 255 },
        glowColor = { 255, 245, 235, 160 },
        skinKey = "pearl",
        effect = { id = "slot_master", name = "口袋大师", desc = "落入不同口袋越多加成越高,+18%/种", diversityBonus = 0.18 },
    },
    {
        name = "黑曜石球", baseValue = 900000, cost = 1e21,
        color = { 160, 120, 200, 255 },
        glowColor = { 120, 80, 180, 200 },
        skinKey = "obsidian",
        effect = { id = "charge", name = "蓄能", desc = "撞钉积蓄能量,落袋时释放(撞钉数²×球价值%)", exponent = 2 },
    },
    {
        name = "琥珀球", baseValue = 3500000, cost = 3e23,
        color = { 230, 170, 50, 255 },
        glowColor = { 255, 200, 80, 180 },
        skinKey = "amber",
        effect = { id = "tempo", name = "节律", desc = "下落速度随时间加快,落袋奖励与速度挂钩", speedGrowth = 0.04, rewardScale = 0.6 },
    },
}

-- ============================================================================
-- 皮肤系统
-- ============================================================================

--- 获取球类型的皮肤图片路径
---@param skinKey string 球的 skinKey
---@return string 图片路径
function M.GetBallSkinImage(skinKey)
    return "image/ball_" .. skinKey .. ".png"
end

--- 获取球类型的所有可用皮肤列表
--- 默认皮肤（"default"）= 原来的纯色圆球，已解锁
--- 图片皮肤（"skin1"）= 生成的球图片，需广告解锁
---@param ballIndex number 球索引（1-based）
---@return table[] 皮肤列表 { id, name, image?, isDefault }
function M.GetBallSkins(ballIndex)
    local bt = M.BALL_TYPES[ballIndex]
    if not bt then return {} end
    return {
        { id = "default", name = "经典", isDefault = true },
        { id = "skin1", name = bt.name, image = M.GetBallSkinImage(bt.skinKey) },
    }
end

-- （天降/自动/多球已迁移至 DRAW_EFFECTS，通过效果等级驱动）

-- ============================================================================
-- 抽取效果池（无限可升级）
-- 每个效果定义: valueFunc(level) 返回数值, costFunc(level) 返回从 level 升到 level+1 的费用
-- descFunc(level, value) 返回描述文本
-- ============================================================================

--- 通用公式：百分比类效果（指数增长）
--- base=Lv.1数值, growth=每级增长倍率
local function pctFormula(base, growth)
    return function(level) return base * (growth ^ (level - 1)) end
end

--- 通用公式：整数类效果（指数增长后取整）
local function intFormula(base, growth)
    return function(level) return math.floor(base * (growth ^ (level - 1))) end
end

--- 通用公式：升级费用
local function costFormula(base, growth)
    return function(level) return math.floor(base * (growth ^ (level - 1))) end
end

--- 通用公式：递减阈值（升级降低触发门槛，有下限）
--- base=Lv.1阈值, decay=每级衰减率, floor=最低阈值
local function thresholdFormula(base, decay, floor)
    return function(level)
        return math.max(floor, math.floor(base * (decay ^ (level - 1))))
    end
end

--- 通用公式：有上限的百分比（趋近 cap）
local function cappedFormula(base, growth, cap)
    return function(level)
        local raw = base * (growth ^ (level - 1))
        return math.min(cap, raw)
    end
end

--- 通用公式：渐进上限（趋近 cap，永不到达）
--- cap=上限值, decay=衰减率（0.95 = 每级保留 95% 的剩余距离）
local function gradualFormula(cap, decay)
    return function(level) return cap * (1 - decay ^ level) end
end

-- ============================================================================
-- 品质系统
-- ============================================================================

M.QUALITY_TIERS = {
    common = { id = "common", name = "普通", color = { 180, 190, 210, 255 }, weight = 40 },
    rare   = { id = "rare",   name = "稀有", color = { 80, 160, 255, 255 },  weight = 30 },
    epic   = { id = "epic",   name = "精良", color = { 180, 80, 255, 255 },  weight = 18 },
    legend = { id = "legend", name = "史诗", color = { 255, 160, 40, 255 },  weight = 8 },
    mythic = { id = "mythic", name = "传说", color = { 255, 60, 60, 255 },   weight = 0 },
}

-- 品质排序顺序（高→低，用于 UI 分组显示）
M.QUALITY_ORDER = { "mythic", "legend", "epic", "rare", "common" }

M.PITY_THRESHOLD = 20

--- 获取品质配置
function M.GetQualityTier(qualityId)
    return M.QUALITY_TIERS[qualityId]
end

-- ============================================================================
-- 附魔系统（广告附魔，可叠加，重复升级）
-- ============================================================================

-- 附魔池（可叠加，重复升级）
-- stacking: "add" = 加算(value*level), "mul" = 乘算(1-(1-value)^level)
M.ENCHANTMENTS = {
    { id = "gem_chance",       name = "宝石猎手", icon = "\xF0\x9F\x92\x8E", color = { 180, 100, 255, 255 }, baseValue = 0.01, stacking = "add",
      descFunc = function(lv) return string.format("撞钉产宝石概率+%d%%", lv) end },
    { id = "peg_split",        name = "分裂之力", icon = "\xF0\x9F\x92\xA5", color = { 255, 120, 50, 255 },  baseValue = 0.05, stacking = "mul",
      descFunc = function(lv) local v = 1 - (1 - 0.05) ^ lv; return string.format("撞钉%.1f%%概率分裂球", v * 100) end },
    { id = "ball_value",       name = "点金术",   icon = "\xF0\x9F\x92\xB0", color = { 255, 220, 50, 255 },  baseValue = 1.00, stacking = "add",
      descFunc = function(lv) return string.format("球基础价值+%d%%", lv * 100) end },
    { id = "upgrade_discount", name = "精打细算", icon = "\xF0\x9F\x8F\xB7\xEF\xB8\x8F",  color = { 100, 200, 150, 255 }, baseValue = 0.05, stacking = "mul",
      descFunc = function(lv) local v = 1 - (1 - 0.05) ^ lv; return string.format("升级金币减少%.1f%%", v * 100) end },
    { id = "extra_ball",       name = "幸运投放", icon = "\xF0\x9F\x8E\xB2", color = { 80, 180, 255, 255 },  baseValue = 0.05, stacking = "add",
      descFunc = function(lv) return string.format("投放%d%%概率多一个球", lv * 5) end },
}

--- 根据 id 查找附魔配置（带缓存）
local _enchantCache = {}
function M.GetEnchantConfig(enchantId)
    if not enchantId then return nil end
    local cached = _enchantCache[enchantId]
    if cached ~= nil then return cached end
    for _, e in ipairs(M.ENCHANTMENTS) do
        if e.id == enchantId then
            _enchantCache[e.id] = e
            return e
        end
    end
    _enchantCache[enchantId] = false
    return nil
end

M.DRAW_EFFECTS = {
    -- === 通用效果（初始值更低，增长更慢，费用更陡） ===
    {
        id = "coin_magnet", name = "金币磁铁",
        color = { 255, 215, 0, 255 },
        quality = "common",
        valueFunc = pctFormula(0.10, 1.18),  -- Lv1=+10%, 每级×1.18
        costFunc = costFormula(2, 1.6),
        descFunc = function(lv, v) return string.format("落袋奖励 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "critical", name = "暴击光环",
        color = { 255, 80, 80, 255 },
        quality = "rare",
        valueFunc = cappedFormula(0.06, 1.15, 0.60),  -- 趋近60%上限，初始略高
        costFunc = costFormula(3, 1.7),
        descFunc = function(lv, v)
            local mult = 2 + math.floor(lv / 6)  -- 每6级+1倍（原8级）
            return string.format("%d%% 概率%d倍收益", math.floor(v * 100), mult)
        end,
    },
    {
        id = "peg_gold", name = "黄金弹钉",
        color = { 255, 200, 50, 255 },
        quality = "common",
        valueFunc = intFormula(2, 1.30),   -- 初始2金币（原1），增长更平缓
        costFunc = costFormula(2, 1.6),
        descFunc = function(lv, v) return "撞钉获得 " .. v .. " 金币" end,
    },
    {
        id = "speed_up", name = "加速",
        color = { 180, 140, 255, 255 },
        quality = "common",
        valueFunc = pctFormula(0.15, 1.18),
        costFunc = costFormula(2, 1.6),
        descFunc = function(lv, v) return string.format("弹珠下落速度 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "extra_ball", name = "额外弹珠",
        color = { 120, 255, 200, 255 },
        quality = "epic",
        valueFunc = intFormula(1, 1.18),  -- 升级很多次才+1球
        costFunc = costFormula(5, 1.8),
        descFunc = function(lv, v) return "每次投放多 " .. v .. " 颗球" end,
    },
    {
        id = "multi_value", name = "增值",
        color = { 80, 180, 255, 255 },
        quality = "common",
        valueFunc = pctFormula(0.12, 1.20),  -- 初始12%（原10%）
        costFunc = costFormula(3, 1.7),
        descFunc = function(lv, v) return string.format("所有球基础价值 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "lucky_bounce", name = "幸运弹跳",
        color = { 100, 230, 120, 255 },
        quality = "rare",
        valueFunc = cappedFormula(0.10, 1.15, 0.70),  -- 初始10%（原8%）
        costFunc = costFormula(3, 1.7),
        descFunc = function(lv, v) return string.format("弹跳偏向高倍口袋 (%.0f%%)", v * 100) end,
    },
    -- === 球型专属效果 ===
    {
        id = "copper_boost", name = "铜球强化",
        color = { 205, 133, 63, 255 },
        quality = "common",
        ballType = "bouncy",
        valueFunc = pctFormula(0.10, 1.20),
        costFunc = costFormula(3, 1.7),
        descFunc = function(lv, v) return string.format("铜球弹力效果 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "silver_boost", name = "银球强化",
        color = { 200, 210, 225, 255 },
        quality = "rare",
        ballType = "split",
        valueFunc = function(level) return level end,
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v)
            local parts = {"阈值-" .. math.min(lv, 3)}
            if lv >= 3 then table.insert(parts, "可重复分裂") end
            if lv >= 5 then table.insert(parts, "分裂" .. (1 + math.floor(lv / 5)) .. "球") end
            return table.concat(parts, " ")
        end,
    },
    {
        id = "gold_boost", name = "金球强化",
        color = { 255, 215, 0, 255 },
        quality = "rare",
        ballType = "midas",
        valueFunc = intFormula(1, 1.35),
        costFunc = costFormula(5, 1.8),
        descFunc = function(lv, v) return "点金撞钉加成 +" .. v end,
    },
    {
        id = "diamond_boost", name = "钻石强化",
        color = { 100, 230, 255, 255 },
        quality = "rare",
        ballType = "crit",
        valueFunc = cappedFormula(0.05, 1.15, 0.60),
        costFunc = costFormula(6, 1.9),
        descFunc = function(lv, v)
            local mult = 2 + math.floor(lv / 5)
            return string.format("暴击概率 +%d%% ×%d倍", math.floor(v * 100), mult)
        end,
    },
    {
        id = "ruby_boost", name = "红宝石强化",
        color = { 230, 50, 80, 255 },
        quality = "epic",
        ballType = "blaze",
        valueFunc = pctFormula(1.5, 1.25),
        costFunc = costFormula(7, 1.9),
        descFunc = function(lv, v) return string.format("灼烧撞钉加成 ×%.1f", v) end,
    },
    {
        id = "emerald_boost", name = "翡翠强化",
        color = { 50, 210, 120, 255 },
        quality = "epic",
        ballType = "fortune",
        valueFunc = pctFormula(0.08, 1.22),
        costFunc = costFormula(7, 1.9),
        descFunc = function(lv, v) return string.format("聚财奖金比例 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "meteor_boost", name = "陨石强化",
        color = { 200, 100, 40, 255 },
        quality = "epic",
        ballType = "impact",
        valueFunc = pctFormula(0.12, 1.22),
        costFunc = costFormula(8, 2.0),
        descFunc = function(lv, v)
            local shake = lv >= 5 and " 强震屏" or (lv >= 3 and " 震屏" or "")
            return string.format("冲击倍率加成 +%d%%%s", math.floor(v * 100), shake)
        end,
    },
    -- === 新球专属效果 ===
    {
        id = "iron_boost", name = "铁球强化",
        color = { 160, 170, 180, 255 },
        quality = "common",
        ballType = "sturdy",
        valueFunc = pctFormula(0.05, 1.20),
        costFunc = costFormula(3, 1.7),
        descFunc = function(lv, v) return string.format("坚韧加成间隔 -1钉, 效果 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "sapphire_boost", name = "蓝宝石强化",
        color = { 40, 80, 220, 255 },
        quality = "epic",
        ballType = "combo_master",
        valueFunc = pctFormula(0.15, 1.20),
        costFunc = costFormula(7, 1.9),
        descFunc = function(lv, v) return string.format("连击宗师倍率 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "combo_echo", name = "连击回响",
        color = { 60, 100, 240, 255 },
        quality = "legend",
        requires = "sapphire_boost",
        valueFunc = pctFormula(0.10, 1.18),
        costFunc = costFormula(7, 2.0),
        descFunc = function(lv, v) return string.format("连击≥5时 落袋额外 +%d%% 连击数", math.floor(v * 100)) end,
    },
    {
        id = "pearl_boost", name = "珍珠强化",
        color = { 240, 230, 220, 255 },
        quality = "epic",
        ballType = "slot_master",
        valueFunc = pctFormula(0.05, 1.20),
        costFunc = costFormula(7, 1.9),
        descFunc = function(lv, v) return string.format("口袋大师每种加成 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "slot_harmony", name = "口袋和声",
        color = { 230, 220, 200, 255 },
        quality = "legend",
        requires = "pearl_boost",
        valueFunc = pctFormula(0.20, 1.20),
        costFunc = costFormula(7, 2.0),
        descFunc = function(lv, v) return string.format("覆盖全部口袋后 +%d%% 持续3s", math.floor(v * 100)) end,
    },
    {
        id = "obsidian_boost", name = "黑曜石强化",
        color = { 50, 40, 60, 255 },
        quality = "epic",
        ballType = "charge",
        valueFunc = pctFormula(0.15, 1.22),
        costFunc = costFormula(8, 2.0),
        descFunc = function(lv, v) return string.format("蓄能释放倍率 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "charge_burst", name = "蓄能爆裂",
        color = { 100, 60, 160, 255 },
        quality = "legend",
        requires = "obsidian_boost",
        valueFunc = thresholdFormula(20, 0.88, 5),  -- Lv1=20, 逐级降低, 最低5
        costFunc = costFormula(8, 2.0),
        descFunc = function(lv, v) return string.format("撞≥%d钉 蓄能释放×2", v) end,
    },
    {
        id = "amber_boost", name = "琥珀强化",
        color = { 230, 170, 50, 255 },
        quality = "epic",
        ballType = "tempo",
        valueFunc = pctFormula(0.10, 1.20),
        costFunc = costFormula(7, 1.9),
        descFunc = function(lv, v) return string.format("节律速度增长 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "tempo_shift", name = "节律变奏",
        color = { 240, 190, 80, 255 },
        quality = "legend",
        requires = "amber_boost",
        valueFunc = pctFormula(0.08, 1.18),
        costFunc = costFormula(7, 2.0),
        descFunc = function(lv, v) return string.format("速度越快 撞钉产金 +%d%%/10%%速度", math.floor(v * 100)) end,
    },
    -- === 高级通用效果 ===
    {
        id = "combo", name = "连击风暴",
        color = { 255, 100, 200, 255 },
        quality = "rare",
        valueFunc = pctFormula(0.05, 1.18),
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v)
            local window = math.min(8, 2 + math.floor(lv / 3))
            return string.format("%ds内连续落袋 +%d%%/次", window, math.floor(v * 100))
        end,
    },
    {
        id = "peg_bonus", name = "弹钉奖金",
        color = { 200, 180, 255, 255 },
        quality = "common",
        valueFunc = pctFormula(0.10, 1.15),
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return string.format("每次撞钉额外 +%d%% 球价值金币", math.floor(v * 100)) end,
    },
    {
        id = "slot_fortune", name = "口袋祝福",
        color = { 255, 180, 100, 255 },
        quality = "epic",
        valueFunc = cappedFormula(0.05, 1.12, 0.50),  -- 趋近50%
        costFunc = costFormula(6, 1.9),
        descFunc = function(lv, v)
            local mult = 2 + math.floor(lv / 8)
            return string.format("%d%% 概率口袋%d倍", math.floor(v * 100), mult)
        end,
    },
    -- === 乘区强化效果（强化结算管线各乘区） ===
    {
        id = "ball_polish", name = "弹珠打磨",
        color = { 160, 200, 255, 255 },
        quality = "common",
        valueFunc = intFormula(3, 1.30),         -- Lv1=+3, Lv5=+10, Lv10=+41
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return "球价值额外 +" .. v end,
    },
    {
        id = "ball_refine", name = "弹珠精炼",
        color = { 120, 180, 255, 255 },
        quality = "common",
        valueFunc = pctFormula(0.06, 1.20),       -- Lv1=+6%, Lv5=+12%, Lv10=+31%
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("球最终价值 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "heavy_landing", name = "重力落袋",
        color = { 200, 140, 80, 255 },
        quality = "rare",
        valueFunc = pctFormula(0.05, 1.18),       -- Lv1=+5%, Lv5=+10%, Lv10=+23%
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("所有球落袋倍率 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "slot_streak", name = "口袋连珠",
        color = { 255, 160, 80, 255 },
        quality = "rare",
        valueFunc = pctFormula(0.08, 1.20),       -- Lv1=+8%/次, Lv5=+17%
        costFunc = costFormula(5, 1.8),
        descFunc = function(lv, v) return string.format("连续落入同口袋 +%d%%/次", math.floor(v * 100)) end,
    },
    {
        id = "windfall", name = "意外之财",
        color = { 80, 220, 160, 255 },
        quality = "rare",
        valueFunc = gradualFormula(0.15, 0.95),   -- 趋近15%上限
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("所有球聚财 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "crit_power", name = "暴击之力",
        color = { 255, 60, 120, 255 },
        quality = "epic",
        valueFunc = pctFormula(0.50, 1.15),       -- Lv1=+0.5倍, Lv5=+0.87倍
        costFunc = costFormula(6, 2.0),
        descFunc = function(lv, v) return string.format("暴击倍率 +%.1f", v) end,
    },
    {
        id = "combo_frenzy", name = "连击狂热",
        color = { 255, 120, 220, 255 },
        quality = "epic",
        valueFunc = pctFormula(0.20, 1.18),       -- Lv1=+20%, Lv5=+39%
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("连击增长率 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "earning_amp", name = "收益放大",
        color = { 255, 220, 80, 255 },
        quality = "epic",
        valueFunc = pctFormula(0.05, 1.18),       -- Lv1=+5%, Lv5=+10%, Lv10=+23%
        costFunc = costFormula(8, 2.0),
        descFunc = function(lv, v) return string.format("最终收益 +%d%%", math.floor(v * 100)) end,
    },
    -- === 弹钉频率派（撞更多钉） ===
    {
        id = "peg_launch", name = "弹钉弹射",
        color = { 200, 120, 255, 255 },
        quality = "common",
        valueFunc = gradualFormula(0.80, 0.95),
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return string.format("撞钉弹跳力 +%d%%", math.floor(v * 100)) end,
    },
    -- === 弹钉收益派（每次撞钉赚更多） ===
    {
        id = "peg_resonance", name = "弹钉共鸣",
        color = { 255, 140, 60, 255 },
        quality = "rare",
        valueFunc = pctFormula(0.03, 1.20),
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return string.format("落袋收益 +%d%%/钉", math.floor(v * 100)) end,
    },
    {
        id = "peg_chain", name = "弹钉连锁",
        color = { 255, 100, 150, 255 },
        quality = "rare",
        valueFunc = pctFormula(0.10, 1.22),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("0.3s内连撞 +%d%%球价值/连", math.floor(v * 100)) end,
    },
    {
        id = "peg_gem", name = "弹钉宝石",
        color = { 130, 200, 255, 255 },
        quality = "mythic",
        valueFunc = gradualFormula(0.25, 0.95),
        costFunc = costFormula(6, 2.0),
        descFunc = function(lv, v) return string.format("撞钉 %d%% 概率掉宝石", math.floor(v * 100)) end,
    },
    -- === 弹钉协作派（多球互动增益） ===
    {
        id = "peg_charge", name = "弹钉充能",
        color = { 50, 230, 180, 255 },
        quality = "rare",
        valueFunc = pctFormula(0.20, 1.20),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("充能钉奖金 +%d%%球价值", math.floor(v * 100)) end,
    },
    {
        id = "peg_mark", name = "弹钉印记",
        color = { 200, 150, 255, 255 },
        quality = "common",
        valueFunc = pctFormula(0.15, 1.18),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("印记钉撞击收益 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "peg_sync", name = "弹钉共振",
        color = { 255, 200, 100, 255 },
        quality = "epic",
        valueFunc = pctFormula(0.04, 1.22),
        costFunc = costFormula(6, 2.0),
        descFunc = function(lv, v) return string.format("每多1球撞钉收益 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "peg_wave", name = "弹钉波动",
        color = { 100, 200, 255, 255 },
        quality = "common",
        valueFunc = gradualFormula(200, 0.95),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("撞钉推动附近球 %d px/s", math.floor(v)) end,
    },
    -- === 独立弹钉效果 ===
    {
        id = "peg_value", name = "弹钉增值",
        color = { 220, 180, 50, 255 },
        quality = "common",
        valueFunc = intFormula(1, 1.20),
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return "撞钉增加球价值 +" .. v end,
    },
    -- === 黄金弹钉增强（需解锁黄金弹钉） ===
    {
        id = "gold_stack", name = "黄金积累",
        color = { 255, 220, 80, 255 },
        quality = "common",
        requires = "peg_gold",
        valueFunc = intFormula(1, 1.20),
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return "撞钉增加黄金产出 +" .. v end,
    },
    {
        id = "gold_crit", name = "黄金暴击",
        color = { 255, 180, 60, 255 },
        quality = "rare",
        requires = "peg_gold",
        valueFunc = gradualFormula(0.30, 0.95),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("%d%% 概率黄金3倍", math.floor(v * 100)) end,
    },
    {
        id = "gold_streak", name = "黄金连击",
        color = { 255, 200, 100, 255 },
        quality = "rare",
        requires = "peg_gold",
        valueFunc = gradualFormula(0.50, 0.95),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("连续撞钉黄金 +%d%%/连", math.floor(v * 100)) end,
    },
    {
        id = "gold_ember", name = "黄金余烬",
        color = { 255, 140, 40, 255 },
        quality = "rare",
        requires = "peg_gold",
        valueFunc = gradualFormula(0.40, 0.95),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("黄金产出后2s持续产金 %d%%", math.floor(v * 100)) end,
    },
    {
        id = "gold_harvest", name = "黄金丰收",
        color = { 255, 230, 120, 255 },
        quality = "legend",
        requires = "peg_gold",
        valueFunc = gradualFormula(0.50, 0.95),
        costFunc = costFormula(6, 2.0),
        descFunc = function(lv, v) return string.format("落袋时额外 +%d%% 总黄金", math.floor(v * 100)) end,
    },
    {
        id = "gold_aura", name = "黄金光环",
        color = { 255, 210, 80, 255 },
        quality = "common",
        requires = "peg_gold",
        valueFunc = gradualFormula(0.50, 0.95),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("附近钉产金 %d%%", math.floor(v * 100)) end,
    },
    -- === 流派A：时间掌控（4效果）===
    {
        id = "time_harvest", name = "时间收割",
        color = { 100, 200, 255, 255 },
        quality = "common",
        valueFunc = pctFormula(0.02, 1.20),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("撞钉延时 +%.2f秒", v) end,
    },
    {
        id = "last_stand", name = "绝境爆发",
        color = { 255, 80, 60, 255 },
        quality = "epic",
        valueFunc = pctFormula(0.10, 1.18),
        costFunc = costFormula(6, 2.0),
        descFunc = function(lv, v) return string.format("剩余≤10s 收益 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "time_crystal", name = "时间结晶",
        color = { 150, 220, 255, 255 },
        quality = "rare",
        valueFunc = pctFormula(0.03, 1.22),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("过关剩余秒×%.2f×口袋均值", v) end,
    },
    {
        id = "haste", name = "急速心流",
        color = { 255, 200, 80, 255 },
        quality = "common",
        valueFunc = pctFormula(0.08, 1.18),
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return string.format("前15s收益 +%d%%", math.floor(v * 100)) end,
    },
    -- === 流派B：连锁反应（4效果）===
    {
        id = "chain_lightning", name = "连锁闪电",
        color = { 120, 180, 255, 255 },
        quality = "rare",
        valueFunc = pctFormula(0.15, 1.20),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("%d%% 概率触发未命中钉", math.floor(v * 100)) end,
    },
    {
        id = "echo_hit", name = "回响打击",
        color = { 200, 160, 255, 255 },
        quality = "rare",
        valueFunc = pctFormula(0.06, 1.22),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("撞≥10钉后 +%d%%球价值/撞", math.floor(v * 100)) end,
    },
    {
        id = "cascade_bonus", name = "级联奖励",
        color = { 255, 180, 120, 255 },
        quality = "epic",
        valueFunc = pctFormula(0.04, 1.20),
        costFunc = costFormula(6, 2.0),
        descFunc = function(lv, v) return string.format("每5钉 +%d%% 落袋收益", math.floor(v * 100)) end,
    },
    {
        id = "overcharge", name = "超载爆发",
        color = { 255, 100, 50, 255 },
        quality = "legend",
        valueFunc = thresholdFormula(15, 0.88, 3),  -- Lv1=15, 逐级降低, 最低3
        costFunc = costFormula(7, 2.0),
        descFunc = function(lv, v) return string.format("撞满%d钉 落袋×3", v) end,
    },
    -- === 流派C：口袋大师（4效果）===
    {
        id = "slot_cycle", name = "口袋轮转",
        color = { 180, 255, 200, 255 },
        quality = "rare",
        valueFunc = pctFormula(0.12, 1.20),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("连落不同口袋 +%d%%/个", math.floor(v * 100)) end,
    },
    {
        id = "slot_jackpot", name = "口袋大奖",
        color = { 255, 215, 0, 255 },
        quality = "legend",
        valueFunc = pctFormula(0.05, 1.18),
        costFunc = costFormula(6, 2.0),
        descFunc = function(lv, v) return string.format("全覆盖后 ×%.1f", 2 + v) end,
    },
    {
        id = "slot_echo", name = "口袋回响",
        color = { 160, 230, 180, 255 },
        quality = "common",
        valueFunc = pctFormula(0.10, 1.20),
        costFunc = costFormula(5, 1.8),
        descFunc = function(lv, v) return string.format("相邻口袋 +%d%% 3秒", math.floor(v * 100)) end,
    },
    {
        id = "hot_slot", name = "热门口袋",
        color = { 255, 160, 60, 255 },
        quality = "common",
        valueFunc = pctFormula(0.05, 1.18),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("最热口袋 +%d%%×次数", math.floor(v * 100)) end,
    },
    -- === 流派D：灼烧蔓延（4效果）===
    {
        id = "burn_spread", name = "灼烧蔓延",
        color = { 255, 80, 40, 255 },
        quality = "rare",
        requires = "ruby_boost",
        valueFunc = gradualFormula(0.40, 0.95),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("%d%% 概率点燃相邻钉", math.floor(v * 100)) end,
    },
    {
        id = "burn_linger", name = "灼烧余温",
        color = { 255, 120, 60, 255 },
        quality = "common",
        requires = "ruby_boost",
        valueFunc = pctFormula(0.08, 1.20),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("灼烧钉撞击额外 ×%.2f产金", v) end,
    },
    {
        id = "burn_climax", name = "灼烧高潮",
        color = { 255, 50, 20, 255 },
        quality = "legend",
        requires = "ruby_boost",
        valueFunc = thresholdFormula(8, 0.88, 2),  -- Lv1=8, 逐级降低, 最低2
        costFunc = costFormula(6, 2.0),
        descFunc = function(lv, v) return string.format("灼烧%d钉 落袋+50%%灼烧收益", v) end,
    },
    {
        id = "burn_empower", name = "灼烧淬炼",
        color = { 230, 100, 50, 255 },
        quality = "common",
        requires = "ruby_boost",
        valueFunc = pctFormula(0.03, 1.20),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("每灼烧1钉 球价值 +%d%%", math.floor(v * 100)) end,
    },
    -- === 流派E：分裂风暴（3效果）===
    {
        id = "split_inherit", name = "分裂传承",
        color = { 200, 220, 240, 255 },
        quality = "rare",
        requires = "silver_boost",
        valueFunc = pctFormula(0.50, 1.18),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("分裂球继承 %d%% 增值", math.floor(v * 100)) end,
    },
    {
        id = "split_frenzy", name = "分裂狂潮",
        color = { 180, 210, 255, 255 },
        quality = "epic",
        requires = "silver_boost",
        valueFunc = pctFormula(0.10, 1.20),
        costFunc = costFormula(6, 2.0),
        descFunc = function(lv, v) return string.format("每颗分裂球 +%d%% 落袋", math.floor(v * 100)) end,
    },
    {
        id = "split_nova", name = "分裂新星",
        color = { 160, 200, 255, 255 },
        quality = "legend",
        requires = "silver_boost",
        valueFunc = pctFormula(0.20, 1.22),
        costFunc = costFormula(7, 2.0),
        descFunc = function(lv, v) return string.format("分裂时范围产金 ×%.2f球价值", v) end,
    },
    -- === 流派F：巨力碾压（3效果）===
    {
        id = "mass_impact", name = "质量冲击",
        color = { 200, 160, 100, 255 },
        quality = "epic",
        valueFunc = pctFormula(0.05, 1.18),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("每撞5钉 落袋 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "gravity_well", name = "引力之井",
        color = { 120, 100, 200, 255 },
        quality = "legend",
        valueFunc = gradualFormula(60, 0.95),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("撞≥5钉后 吸引%dpx内球偏向弹钉", math.floor(v)) end,
    },
    {
        id = "growth_momentum", name = "成长动能",
        color = { 180, 140, 80, 255 },
        quality = "common",
        valueFunc = pctFormula(0.01, 1.20),
        costFunc = costFormula(6, 2.0),
        descFunc = function(lv, v) return string.format("每撞1钉 球价值 +%d%%", math.floor(v * 100)) end,
    },
    -- === 连击补强（+2 效果）===
    {
        id = "combo_extend", name = "连击延续",
        color = { 255, 140, 200, 255 },
        quality = "common",
        valueFunc = pctFormula(0.10, 1.18),
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return string.format("撞钉延长连击窗口 +%.2f秒", v) end,
    },
    {
        id = "combo_burst", name = "连击爆发",
        color = { 255, 60, 180, 255 },
        quality = "epic",
        valueFunc = thresholdFormula(10, 0.88, 3),  -- Lv1=10, 逐级降低, 最低3
        costFunc = costFormula(6, 2.0),
        descFunc = function(lv, v) return string.format("连击达%d次 落袋×2 (每轮3次)", v) end,
    },
    -- === 聚财补强（+2 效果）===
    {
        id = "fortune_stack", name = "聚财积累",
        color = { 60, 230, 140, 255 },
        quality = "common",
        valueFunc = pctFormula(0.02, 1.20),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("聚财落袋后 聚财比例 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "fortune_share", name = "聚财共享",
        color = { 80, 220, 180, 255 },
        quality = "epic",
        valueFunc = gradualFormula(0.50, 0.95),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("聚财落袋后3s 其他球+%.0f%%聚财", v * 100) end,
    },
    -- === 暴击补强（+2 效果）===
    {
        id = "crit_streak", name = "暴击连锁",
        color = { 255, 100, 100, 255 },
        quality = "epic",
        valueFunc = pctFormula(0.30, 1.18),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("连续暴击 倍率+%.1f/次", v) end,
    },
    {
        id = "crit_shock", name = "暴击震荡",
        color = { 255, 50, 50, 255 },
        quality = "legend",
        valueFunc = pctFormula(0.05, 1.20),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("暴击时 30px内钉产金 ×%d%%球价值", math.floor(v * 100)) end,
    },
    -- === 分裂补强（+1 效果）===
    {
        id = "split_vitality", name = "分裂活力",
        color = { 170, 210, 255, 255 },
        quality = "legend",
        requires = "silver_boost",
        valueFunc = thresholdFormula(5, 0.88, 2),  -- Lv1=5, 逐级降低, 最低2
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("分裂球撞≥%d钉 落袋×1.5", v) end,
    },
    -- === 巨力补强（+1 效果）===
    {
        id = "mass_quake", name = "碾压震颤",
        color = { 200, 140, 60, 255 },
        quality = "mythic",
        valueFunc = pctFormula(0.02, 1.20),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("撞≥15钉落袋 全场钉产金 %d%%球价值", math.floor(v * 100)) end,
    },
    -- === 功能型效果 ===
    {
        id = "sky_drop", name = "天降弹珠",
        color = { 160, 170, 230, 255 },
        quality = "common",
        category = "func",
        valueFunc = function(level)
            -- Lv.1=5s, 每级缩短更慢，最低0.5s（原6s起始）
            return math.max(0.5, 5.0 * (0.85 ^ (level - 1)))
        end,
        costFunc = costFormula(2, 1.6),
        descFunc = function(lv, v) return string.format("每 %.1f 秒天降弹珠", v) end,
    },
    {
        id = "auto_drop", name = "自动投放",
        color = { 100, 230, 120, 255 },
        quality = "mythic",
        category = "func",
        valueFunc = function(level)
            -- Lv.1=2.5s, 每级缩短更慢，最低0.4s（原3s起始）
            return math.max(0.4, 2.5 * (0.82 ^ (level - 1)))
        end,
        costFunc = costFormula(3, 1.7),
        descFunc = function(lv, v) return string.format("每 %.1f 秒自动投放", v) end,
    },
    {
        id = "multi_drop", name = "多球投放",
        color = { 180, 140, 255, 255 },
        quality = "mythic",
        category = "func",
        valueFunc = intFormula(1, 1.18),  -- 升级很多次才+1球
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return string.format("每次投放 %d 颗额外球", v) end,
    },
    {
        id = "auto_drop_upgrade", name = "精英投放",
        color = { 255, 200, 100, 255 },
        quality = "mythic",
        category = "func",
        valueFunc = intFormula(1, 1.25),  -- Lv.1=+1级, 缓慢增长
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return string.format("自动投放球品质 +%d 级", v) end,
    },
    {
        id = "drop_level_boost", name = "超频投射",
        color = { 255, 120, 200, 255 },
        quality = "mythic",
        category = "func",
        valueFunc = intFormula(2, 1.18),  -- Lv.1=+2级, Lv.2=+2, Lv.5=+3 ...
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return string.format("投球等级 +%d（价值与成本同步提升）", v) end,
    },
}

M.DRAW_COST = 3            -- 宝石（首次抽取费用）
M.DRAW_COST_MULTIPLIER = 1.3  -- 每次抽取费用增长（原1.4，降低后期抽取压力）

-- 轮次系统配置
M.ROUND = {
    TIME_LIMIT = 60,           -- 每轮时间（秒）
    BASE_TARGET = 20,          -- 第1轮目标值（铁球baseValue=2，更容易达成）
    GROWTH_RATE = 1.28,        -- 目标值每轮增长倍率（平缓增长，给玩家升级空间）
}

return M
