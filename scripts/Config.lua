-- ============================================================================
-- Config.lua - 配置聚合入口
-- 所有子模块拆分到 Config/ 目录，此文件合并导出，外部引用方式不变
-- ============================================================================

local Board   = require("Config.Board")
local Balls   = require("Config.Balls")
local Quality = require("Config.Quality")
local Effects = require("Config.Effects")
local Round   = require("Config.Round")
local Idle    = require("Config.Idle")

local M = {}

-- === Board（弹珠台布局与物理） ===
M.CONFIG           = Board.CONFIG
M.GOOD_MULT_POOL   = Board.GOOD_MULT_POOL
M.GetSlotMult      = Board.GetSlotMult
M.GetSlotUpgradeCost = Board.GetSlotUpgradeCost
M.GetMultColor     = Board.GetMultColor

-- === Balls（钢珠类型与皮肤） ===
M.BALL_TYPES       = Balls.BALL_TYPES
M.SLOT_UNLOCK_COSTS = Balls.SLOT_UNLOCK_COSTS
M.GetBallSkinImage = Balls.GetBallSkinImage
M.GetBallSkins     = Balls.GetBallSkins

-- === Quality（品质与附魔） ===
M.QUALITY_TIERS    = Quality.QUALITY_TIERS
M.QUALITY_ORDER    = Quality.QUALITY_ORDER
M.PITY_THRESHOLD   = Quality.PITY_THRESHOLD
M.GetQualityTier   = Quality.GetQualityTier
M.ENCHANTMENTS     = Quality.ENCHANTMENTS
M.GetEnchantConfig = Quality.GetEnchantConfig

-- === Effects（抽取效果池） ===
M.DRAW_EFFECTS     = Effects.DRAW_EFFECTS

-- === Round（主线轮次与抽取费用） ===
M.ROUND            = Round.ROUND
M.DRAW_COST        = Round.DRAW_COST
M.DRAW_COST_MULTIPLIER = Round.DRAW_COST_MULTIPLIER

-- === Idle（放置模式） ===
M.IDLE                  = Idle.IDLE
M.BALL_UPGRADES         = Idle.BALL_UPGRADES           -- 兼容旧接口（默认铁球）
M.BALL_UPGRADES_BY_TYPE = Idle.BALL_UPGRADES_BY_TYPE   -- 按球类型索引
M.GetBallUpgradesForType = Idle.GetBallUpgradesForType  -- 获取指定球类型升级列表
M.GetUpgradeCost        = Idle.GetUpgradeCost
M.GetPrestigeAbilityCost   = Idle.GetPrestigeAbilityCost
M.GetPrestigeAbilityConfig = Idle.GetPrestigeAbilityConfig

return M
