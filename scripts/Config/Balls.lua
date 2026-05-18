-- ============================================================================
-- Config/Balls.lua - 钢珠类型、皮肤系统
-- ============================================================================

local M = {}

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

-- 解锁新坑位费用（10个口袋默认全部解锁，无需额外解锁）
M.SLOT_UNLOCK_COSTS = {}

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
---@param ballIndex number 球索引（1-based）
---@return table[] 皮肤列表
function M.GetBallSkins(ballIndex)
    local bt = M.BALL_TYPES[ballIndex]
    if not bt then return {} end
    return {
        { id = "default", name = "经典", isDefault = true },
        { id = "skin1", name = bt.name, image = M.GetBallSkinImage(bt.skinKey) },
    }
end

return M
