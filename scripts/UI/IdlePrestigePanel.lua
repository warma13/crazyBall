-- ============================================================================
-- UI/IdlePrestigePanel.lua - 放置模式转生面板（含星尘能力树）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local BigNum = require("BigNum")
local State = require("State")

local gameState = State.gameState

local P = {}

-- 星尘图标路径
local STARDUST_IMG = "image/stardust_icon_20260520052152.png"

-- UI 卡片背景图（九宫格切图）
local IMG = {
    CARD       = "image/ui_card_normal_20260517160219.png",
    CARD_HL    = "image/ui_card_highlight_20260517160012.png",
}
local CARD_SLICE = { top = 20, right = 20, bottom = 20, left = 20 }

-- ── 轻量更新引用 ──
local abilityRefs = {}   -- { [abilityId] = { costLabel, levelLabel, btn, ... } }
local headerRefs = {}    -- { stardustLabel, multLabel }

-- ============================================================================
-- 颜色常量
-- ============================================================================

local CLR = {
    TIER_BG     = {
        { 30, 28, 50, 200 },   -- T1
        { 35, 25, 60, 200 },   -- T2
        { 45, 20, 70, 200 },   -- T3
    },
    TIER_BORDER = {
        { 80, 70, 140, 160 },   -- T1
        { 100, 60, 180, 160 },  -- T2
        { 140, 50, 200, 160 },  -- T3
    },
    TIER_TITLE  = {
        { 150, 180, 255, 255 },  -- T1 蓝
        { 180, 140, 255, 255 },  -- T2 紫
        { 255, 180, 100, 255 },  -- T3 金
    },
    LOCKED      = { 80, 80, 100, 150 },
    STARDUST    = { 200, 180, 255, 255 },
    CAN_BUY     = { 100, 60, 200, 240 },
    CAN_BUY_BD  = { 160, 120, 255, 200 },
    CANT_BUY    = { 40, 40, 55, 200 },
    CANT_BUY_BD = { 70, 70, 90, 120 },
    MAXED       = { 60, 150, 100, 200 },
    MAXED_BD    = { 80, 200, 140, 180 },
    PRESTIGE_ON = { 120, 60, 200, 240 },
    PRESTIGE_OFF= { 50, 50, 65, 180 },
}

local TIER_NAMES = { "T1 · 初觉", "T2 · 精进", "T3 · 超越" }
local TIER_UNLOCK_HINT = {
    "",
    "需要任意 T1 能力 ≥ Lv.3 解锁",
    "需要任意 T2 能力 ≥ Lv.3 解锁",
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

local function GetIdleMode()
    return require("IdleMode")
end

--- 信息行
local function InfoRow(label, value, valueColor)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        padding = { 3, 4, 3, 4 },
        children = {
            UI.Label {
                text = label,
                fontSize = 12,
                fontColor = { 150, 160, 190, 200 },
            },
            UI.Label {
                text = value,
                fontSize = 12,
                fontColor = valueColor or { 220, 220, 240, 240 },
                fontWeight = "bold",
            },
        },
    }
end

-- ============================================================================
-- 能力卡片
-- ============================================================================

--- 创建单个能力卡片
local function CreateAbilityCard(cfg, cb, tierUnlocked)
    local M = GetIdleMode()
    local lv = M.GetPrestigeAbilityLevel(cfg.id)
    local rawLevel = lv  -- 等级快照，用于防连点
    local cost = Config.GetPrestigeAbilityCost(cfg, lv)
    local isMaxed = (cfg.maxLevel and lv >= cfg.maxLevel)
    local canBuy = tierUnlocked and not isMaxed and (cost ~= math.huge) and (gameState.idleStardust >= cost)

    -- 效果文本
    local effectText
    if cfg.id == "starlight_savings" then
        effectText = lv > 0 and string.format("初始金币 %s", State.FormatNumber(M.GetPrestigeStartCoins())) or "转生后获初始金币"
    elseif cfg.id == "ball_mastery" then
        effectText = string.format("弹珠能力等级 +%d", M.GetBallMasteryBonus())
    elseif cfg.id == "skill_ember" then
        local r = M.GetSkillEmberCDReduction()
        effectText = string.format("技能 CD -%d%%", math.floor(r * 100 + 0.5))
    elseif cfg.id == "nebula_multiply" then
        effectText = string.format("收益 +%d%%", lv * 8)
    elseif cfg.id == "split_resonance" then
        local reg, storm = M.GetSplitResonanceBonus()
        effectText = string.format("分裂+%d / 风暴+%d", reg, storm)
    elseif cfg.id == "crit_star" then
        local cr, cm = M.GetCritStarBonus()
        effectText = string.format("暴击率+%d%% 倍率+%.2fx", math.floor(cr + 0.5), cm)
    elseif cfg.id == "combo_resonance" then
        local w, p = M.GetComboResonanceBonus()
        effectText = string.format("窗口+%.1fs 加成+%d%%", w, math.floor(p * 100 + 0.5))
    elseif cfg.id == "skill_overload" then
        effectText = string.format("技能效果 +%d%%", lv * 10)
    elseif cfg.id == "supernova" then
        effectText = string.format("星尘获取 +%d%%", lv * 15)
    elseif cfg.id == "void_force" then
        effectText = string.format("门槛降低 %d%%", lv * 4)
    else
        effectText = cfg.desc
    end

    -- 等级文本
    local levelText
    if cfg.maxLevel then
        levelText = string.format("Lv.%d/%d", lv, cfg.maxLevel)
    else
        levelText = string.format("Lv.%d", lv)
    end

    -- 卡片背景图 + 色调
    local cardImg, cardTint
    if isMaxed then
        cardImg = IMG.CARD_HL
        cardTint = { 60, 150, 100, 200 }
    elseif canBuy then
        cardImg = IMG.CARD_HL
        cardTint = { 120, 80, 220, 220 }
    else
        cardImg = IMG.CARD
        cardTint = nil
    end

    local refs = {}
    abilityRefs[cfg.id] = refs

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        padding = { 8, 12, 8, 12 },
        marginBottom = 4,
        borderRadius = 10,
        backgroundImage = cardImg,
        backgroundFit = "sliced",
        backgroundSlice = CARD_SLICE,
        imageTint = cardTint,
        alignItems = "center",
        gap = 8,
        pointerEvents = "auto",
        onClick = function()
            -- 防连点：如果等级已被其他点击升过，跳过
            if M.GetPrestigeAbilityLevel(cfg.id) ~= rawLevel then return end
            if not canBuy then return end
            cb.PlayClickSfx()
            cb.PurchasePrestigeAbility(cfg.id)
        end,
        children = {
            -- 图标
            UI.Panel {
                width = 36, height = 36,
                borderRadius = 8,
                backgroundImage = cfg.iconImg,
                backgroundFit = "cover",
            },
            -- 信息区
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                gap = 2, pointerEvents = "none",
                children = {
                    -- 名称 + 等级行
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label {
                                text = cfg.name,
                                fontSize = 13,
                                fontColor = { 230, 230, 250, 255 },
                                fontWeight = "bold",
                            },
                            UI.Panel {
                                padding = { 4, 1, 4, 1 },
                                borderRadius = 3,
                                backgroundColor = isMaxed
                                    and { 255, 200, 50, 40 }
                                    or { 120, 80, 220, 30 },
                                children = {
                                    UI.Label {
                                        text = levelText,
                                        fontSize = 10,
                                        fontColor = isMaxed
                                            and { 255, 220, 80, 255 }
                                            or (lv > 0 and { 180, 220, 255, 240 } or { 120, 120, 140, 160 }),
                                        ref = function(r) refs.levelLabel = r end,
                                    },
                                },
                            },
                        },
                    },
                    -- 效果描述
                    UI.Label {
                        text = effectText,
                        fontSize = 11,
                        fontColor = lv > 0 and { 160, 200, 240, 220 } or { 130, 140, 160, 180 },
                    },
                },
            },
            -- 右侧升级按钮
            UI.Panel {
                minWidth = 52,
                padding = { 8, 5, 8, 5 },
                borderRadius = 6,
                flexShrink = 0,
                backgroundColor = (not tierUnlocked or isMaxed)
                    and { 50, 50, 40, 180 }
                    or (canBuy and { 80, 50, 160, 230 } or { 40, 42, 58, 200 }),
                borderColor = (not tierUnlocked or isMaxed)
                    and { 80, 80, 60, 100 }
                    or (canBuy and { 140, 100, 230, 150 } or { 55, 60, 80, 100 }),
                borderWidth = 1,
                justifyContent = "center", alignItems = "center",
                pointerEvents = "none",
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 3,
                        children = (not tierUnlocked)
                            and {
                                UI.Label {
                                    text = "🔒",
                                    fontSize = 12,
                                    fontColor = CLR.LOCKED,
                                    textAlign = "center",
                                },
                            }
                            or isMaxed
                            and {
                                UI.Label {
                                    text = "MAX",
                                    fontSize = 12,
                                    fontColor = { 200, 180, 80, 200 },
                                    textAlign = "center",
                                },
                            }
                            or {
                                UI.Panel {
                                    width = 14, height = 14,
                                    backgroundImage = STARDUST_IMG,
                                    backgroundFit = "contain",
                                },
                                UI.Label {
                                    text = tostring(cost),
                                    fontSize = 12,
                                    fontColor = canBuy
                                        and { 220, 200, 255, 255 }
                                        or { 110, 115, 140, 180 },
                                    textAlign = "center",
                                    ref = function(r) refs.costLabel = r end,
                                },
                            },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 层级区块
-- ============================================================================

local function CreateTierSection(tier, cb)
    local M = GetIdleMode()
    local unlocked = M.IsTierUnlocked(tier)

    local titleColor = CLR.TIER_TITLE[tier] or { 200, 200, 200, 255 }

    -- 预先构建 children（避免 table.unpack 在表构造器中的稀疏数组陷阱）
    local children = {
        -- 层级标题行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            marginBottom = 4,
            children = {
                UI.Label {
                    text = TIER_NAMES[tier],
                    fontSize = 13,
                    fontColor = titleColor,
                    fontWeight = "bold",
                },
                unlocked and UI.Label {
                    text = "✓ 已解锁",
                    fontSize = 11,
                    fontColor = { 100, 200, 140, 200 },
                } or UI.Label {
                    text = "🔒 锁定",
                    fontSize = 11,
                    fontColor = CLR.LOCKED,
                },
            },
        },
    }

    -- 解锁提示
    if not unlocked then
        children[#children + 1] = UI.Label {
            text = TIER_UNLOCK_HINT[tier],
            fontSize = 10,
            fontColor = { 140, 130, 170, 180 },
            marginBottom = 4,
        }
    end

    -- 能力卡片
    for _, cfg in ipairs(Config.IDLE.PRESTIGE_ABILITIES) do
        if cfg.tier == tier then
            children[#children + 1] = CreateAbilityCard(cfg, cb, unlocked)
        end
    end

    return UI.Panel {
        width = "100%",
        marginBottom = 8,
        padding = { 8, 8, 8, 8 },
        borderRadius = 10,
        backgroundColor = CLR.TIER_BG[tier],
        borderColor = CLR.TIER_BORDER[tier],
        borderWidth = 1,
        gap = 4,
        children = children,
    }
end

-- ============================================================================
-- 主面板
-- ============================================================================

--- 创建转生面板
---@param cb table 回调表
---@return table UI 面板
function P.CreatePrestigePanel(cb)
    local M = GetIdleMode()
    local canPrestige = cb.CanPrestige()
    local threshold = M.GetPrestigeThreshold()
    local stardust = gameState.idleStardust
    local stardustReward = M.GetStardustReward()

    -- 重置引用
    abilityRefs = {}
    headerRefs = {}

    return UI.Panel {
        id = "idlePrestigePanel",
        width = "100%",
        gap = 4,
        alignItems = "center",
        padding = { 4, 10, 4, 10 },
        children = {
            -- ── 星尘余额栏 ──
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                gap = 6,
                padding = { 6, 8, 6, 8 },
                marginBottom = 2,
                borderRadius = 8,
                backgroundColor = { 40, 30, 70, 180 },
                borderColor = { 100, 80, 180, 140 },
                borderWidth = 1,
                children = {
                    UI.Panel {
                        width = 22, height = 22,
                        backgroundImage = STARDUST_IMG,
                        backgroundFit = "contain",
                    },
                    UI.Label {
                        text = tostring(stardust),
                        fontSize = 18,
                        fontColor = CLR.STARDUST,
                        fontWeight = "bold",
                        ref = function(r) headerRefs.stardustLabel = r end,
                    },
                    UI.Label {
                        text = "星尘",
                        fontSize = 12,
                        fontColor = { 160, 140, 200, 200 },
                    },
                },
            },

            -- ── 转生信息区 ──
            UI.Panel {
                width = "100%",
                padding = { 4, 6, 4, 6 },
                gap = 1,
                children = {
                    InfoRow("转生次数", tostring(gameState.idlePrestigeCount)),
                    InfoRow("永久倍率", string.format("x%.1f", gameState.idlePrestigeMult)),
                    InfoRow("累计收益", State.FormatNumber(gameState.idleTotalEarned)),
                    InfoRow("转生门槛", State.FormatNumber(threshold)),
                    canPrestige and UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        padding = { 3, 4, 3, 4 },
                        children = {
                            UI.Label {
                                text = "预计星尘",
                                fontSize = 12,
                                fontColor = { 150, 160, 190, 200 },
                            },
                            UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 3,
                                children = {
                                    UI.Label {
                                        text = string.format("+%d", stardustReward),
                                        fontSize = 12,
                                        fontColor = { 220, 180, 255, 255 },
                                        fontWeight = "bold",
                                    },
                                    UI.Panel {
                                        width = 14, height = 14,
                                        backgroundImage = STARDUST_IMG,
                                        backgroundFit = "contain",
                                    },
                                },
                            },
                        },
                    } or nil,
                },
            },

            -- ── 转生按钮 ──
            UI.Panel {
                width = "90%",
                padding = { 10, 8, 10, 8 },
                marginBottom = 4,
                borderRadius = 10,
                backgroundColor = canPrestige and CLR.PRESTIGE_ON or CLR.PRESTIGE_OFF,
                borderColor = canPrestige and CLR.CAN_BUY_BD or CLR.CANT_BUY_BD,
                borderWidth = 2,
                justifyContent = "center", alignItems = "center",
                pointerEvents = "auto",
                onClick = function()
                    if canPrestige then
                        cb.PlayClickSfx()
                        cb.DoPrestige()
                    end
                end,
                children = {
                    canPrestige and UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "center",
                        gap = 4,
                        children = {
                            UI.Label {
                                text = string.format("转生 (+%d", stardustReward),
                                fontSize = 16,
                                fontColor = { 255, 255, 255, 255 },
                                fontWeight = "bold",
                            },
                            UI.Panel {
                                width = 16, height = 16,
                                backgroundImage = STARDUST_IMG,
                                backgroundFit = "contain",
                            },
                            UI.Label {
                                text = ")",
                                fontSize = 16,
                                fontColor = { 255, 255, 255, 255 },
                                fontWeight = "bold",
                            },
                        },
                    } or UI.Label {
                        text = "转生（未达门槛）",
                        fontSize = 16,
                        fontColor = { 120, 120, 140, 150 },
                        fontWeight = "bold",
                        textAlign = "center",
                    },
                },
            },

            -- ── 分隔线 ──
            UI.Panel {
                width = "90%", height = 1,
                backgroundColor = { 80, 60, 160, 100 },
                marginTop = 2, marginBottom = 4,
            },

            -- ── 能力标题 ──
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 5,
                marginBottom = 4,
                children = {
                    UI.Panel {
                        width = 16, height = 16,
                        backgroundImage = STARDUST_IMG,
                        backgroundFit = "contain",
                    },
                    UI.Label {
                        text = "星尘能力",
                        fontSize = 15,
                        fontColor = { 200, 170, 255, 255 },
                        fontWeight = "bold",
                    },
                },
            },

            -- ── T1 / T2 / T3 ──
            CreateTierSection(1, cb),
            CreateTierSection(2, cb),
            CreateTierSection(3, cb),

            -- ── 底部留白 ──
            UI.Panel { width = "100%", height = 20 },
        },
    }
end

return P
