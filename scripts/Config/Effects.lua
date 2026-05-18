-- ============================================================================
-- Config/Effects.lua - 抽取效果池（DRAW_EFFECTS）
-- ============================================================================

local M = {}

-- ============================================================================
-- 通用公式工具
-- ============================================================================

--- 百分比类效果（指数增长）
local function pctFormula(base, growth)
    return function(level) return base * (growth ^ (level - 1)) end
end

--- 整数类效果（指数增长后取整）
local function intFormula(base, growth)
    return function(level) return math.floor(base * (growth ^ (level - 1))) end
end

--- 升级费用
local function costFormula(base, growth)
    return function(level) return math.floor(base * (growth ^ (level - 1))) end
end

--- 递减阈值（升级降低触发门槛，有下限）
local function thresholdFormula(base, decay, floor)
    return function(level)
        return math.max(floor, math.floor(base * (decay ^ (level - 1))))
    end
end

--- 有上限的百分比（趋近 cap）
local function cappedFormula(base, growth, cap)
    return function(level)
        local raw = base * (growth ^ (level - 1))
        return math.min(cap, raw)
    end
end

--- 渐进上限（趋近 cap，永不到达）
local function gradualFormula(cap, decay)
    return function(level) return cap * (1 - decay ^ level) end
end

-- ============================================================================
-- 抽取效果池
-- ============================================================================

M.DRAW_EFFECTS = {
    -- === 通用效果 ===
    {
        id = "coin_magnet", name = "金币磁铁",
        color = { 255, 215, 0, 255 },
        quality = "common",
        valueFunc = pctFormula(0.10, 1.18),
        costFunc = costFormula(2, 1.6),
        descFunc = function(lv, v) return string.format("落袋奖励 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "critical", name = "暴击光环",
        color = { 255, 80, 80, 255 },
        quality = "rare",
        valueFunc = cappedFormula(0.06, 1.15, 0.60),
        costFunc = costFormula(3, 1.7),
        descFunc = function(lv, v)
            local mult = 2 + math.floor(lv / 6)
            return string.format("%d%% 概率%d倍收益", math.floor(v * 100), mult)
        end,
    },
    {
        id = "peg_gold", name = "黄金弹钉",
        color = { 255, 200, 50, 255 },
        quality = "common",
        valueFunc = intFormula(2, 1.30),
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
        valueFunc = intFormula(1, 1.18),
        costFunc = costFormula(5, 1.8),
        descFunc = function(lv, v) return "每次投放多 " .. v .. " 颗球" end,
    },
    {
        id = "multi_value", name = "增值",
        color = { 80, 180, 255, 255 },
        quality = "common",
        valueFunc = pctFormula(0.12, 1.20),
        costFunc = costFormula(3, 1.7),
        descFunc = function(lv, v) return string.format("所有球基础价值 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "lucky_bounce", name = "幸运弹跳",
        color = { 100, 230, 120, 255 },
        quality = "rare",
        valueFunc = cappedFormula(0.10, 1.15, 0.70),
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
        valueFunc = thresholdFormula(20, 0.88, 5),
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
        valueFunc = cappedFormula(0.05, 1.12, 0.50),
        costFunc = costFormula(6, 1.9),
        descFunc = function(lv, v)
            local mult = 2 + math.floor(lv / 8)
            return string.format("%d%% 概率口袋%d倍", math.floor(v * 100), mult)
        end,
    },
    -- === 乘区强化效果 ===
    {
        id = "ball_polish", name = "弹珠打磨",
        color = { 160, 200, 255, 255 },
        quality = "common",
        valueFunc = intFormula(3, 1.30),
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return "球价值额外 +" .. v end,
    },
    {
        id = "ball_refine", name = "弹珠精炼",
        color = { 120, 180, 255, 255 },
        quality = "common",
        valueFunc = pctFormula(0.06, 1.20),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("球最终价值 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "heavy_landing", name = "重力落袋",
        color = { 200, 140, 80, 255 },
        quality = "rare",
        valueFunc = pctFormula(0.05, 1.18),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("所有球落袋倍率 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "slot_streak", name = "口袋连珠",
        color = { 255, 160, 80, 255 },
        quality = "rare",
        valueFunc = pctFormula(0.08, 1.20),
        costFunc = costFormula(5, 1.8),
        descFunc = function(lv, v) return string.format("连续落入同口袋 +%d%%/次", math.floor(v * 100)) end,
    },
    {
        id = "windfall", name = "意外之财",
        color = { 80, 220, 160, 255 },
        quality = "rare",
        valueFunc = gradualFormula(0.15, 0.95),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("所有球聚财 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "crit_power", name = "暴击之力",
        color = { 255, 60, 120, 255 },
        quality = "epic",
        valueFunc = pctFormula(0.50, 1.15),
        costFunc = costFormula(6, 2.0),
        descFunc = function(lv, v) return string.format("暴击倍率 +%.1f", v) end,
    },
    {
        id = "combo_frenzy", name = "连击狂热",
        color = { 255, 120, 220, 255 },
        quality = "epic",
        valueFunc = pctFormula(0.20, 1.18),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("连击增长率 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "earning_amp", name = "收益放大",
        color = { 255, 220, 80, 255 },
        quality = "epic",
        valueFunc = pctFormula(0.05, 1.18),
        costFunc = costFormula(8, 2.0),
        descFunc = function(lv, v) return string.format("最终收益 +%d%%", math.floor(v * 100)) end,
    },
    -- === 弹钉频率派 ===
    {
        id = "peg_magnet", name = "弹钉磁场",
        color = { 100, 180, 255, 255 },
        quality = "common",
        valueFunc = gradualFormula(0.80, 0.95),
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return string.format("弹钉碰撞半径 +%d%%", math.floor(v * 100)) end,
    },
    {
        id = "peg_slow", name = "弹钉减速",
        color = { 80, 200, 200, 255 },
        quality = "common",
        valueFunc = gradualFormula(0.50, 0.95),
        costFunc = costFormula(4, 1.7),
        descFunc = function(lv, v) return string.format("撞钉后球速 -%d%%", math.floor(v * 100)) end,
    },
    {
        id = "peg_spark", name = "弹钉火花",
        color = { 255, 180, 50, 255 },
        quality = "rare",
        valueFunc = gradualFormula(0.50, 0.95),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("%d%% 概率触发相邻钉", math.floor(v * 100)) end,
    },
    {
        id = "peg_launch", name = "弹钉弹射",
        color = { 200, 120, 255, 255 },
        quality = "common",
        valueFunc = gradualFormula(0.80, 0.95),
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return string.format("撞钉弹跳力 +%d%%", math.floor(v * 100)) end,
    },
    -- === 弹钉收益派 ===
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
    -- === 弹钉协作派 ===
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
    -- === 黄金弹钉增强 ===
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
    -- === 流派A：时间掌控 ===
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
    -- === 流派B：连锁反应 ===
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
        valueFunc = thresholdFormula(15, 0.88, 3),
        costFunc = costFormula(7, 2.0),
        descFunc = function(lv, v) return string.format("撞满%d钉 落袋×3", v) end,
    },
    -- === 流派C：口袋大师 ===
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
    -- === 流派D：灼烧蔓延 ===
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
        valueFunc = thresholdFormula(8, 0.88, 2),
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
    -- === 流派E：分裂风暴 ===
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
    -- === 流派F：巨力碾压 ===
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
    -- === 连击补强 ===
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
        valueFunc = thresholdFormula(10, 0.88, 3),
        costFunc = costFormula(6, 2.0),
        descFunc = function(lv, v) return string.format("连击达%d次 落袋×2 (每轮3次)", v) end,
    },
    -- === 聚财补强 ===
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
    -- === 暴击补强 ===
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
    -- === 分裂补强 ===
    {
        id = "split_vitality", name = "分裂活力",
        color = { 170, 210, 255, 255 },
        quality = "legend",
        requires = "silver_boost",
        valueFunc = thresholdFormula(5, 0.88, 2),
        costFunc = costFormula(5, 1.9),
        descFunc = function(lv, v) return string.format("分裂球撞≥%d钉 落袋×1.5", v) end,
    },
    -- === 巨力补强 ===
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
        valueFunc = intFormula(1, 1.18),
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return string.format("每次投放 %d 颗额外球", v) end,
    },
    {
        id = "auto_drop_upgrade", name = "精英投放",
        color = { 255, 200, 100, 255 },
        quality = "mythic",
        category = "func",
        valueFunc = intFormula(1, 1.25),
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return string.format("自动投放球品质 +%d 级", v) end,
    },
    {
        id = "drop_level_boost", name = "超频投射",
        color = { 255, 120, 200, 255 },
        quality = "mythic",
        category = "func",
        valueFunc = intFormula(2, 1.18),
        costFunc = costFormula(4, 1.8),
        descFunc = function(lv, v) return string.format("投球等级 +%d（价值与成本同步提升）", v) end,
    },
}

return M
