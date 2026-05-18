-- ============================================================================
-- UI/IdleUpgradePanel.lua - 放置模式全局升级面板
-- 使用金币购买永久升级（掉落冷却、基础价值、暴击概率/倍率、底袋强化）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local State = require("State")
local BigNum = require("BigNum")

local gameState = State.gameState

local P = {}

-- UI 背景图路径
local IMG = {
    CARD       = "image/ui_card_normal_20260517160219.png",
    CARD_HL    = "image/ui_card_highlight_20260517160012.png",
    POPUP      = "image/ui_popup_bg_20260517160108.png",
}
local CARD_SLICE = { top = 20, right = 20, bottom = 20, left = 20 }

--- 获取指定升级的当前等级
---@param upgradeId string
---@return number
local function GetLevel(upgradeId)
    return gameState.idleUpgradeLevels[upgradeId] or 0
end

--- 图标颜色映射
local ICON_COLORS = {
    -- Tier 1
    drop_cooldown  = { 80, 200, 255 },
    base_value     = { 255, 180, 60 },
    peg_gold       = { 255, 200, 50 },
    -- Tier 2
    coin_magnet    = { 255, 215, 0 },
    crit_chance    = { 255, 80, 80 },
    -- Tier 3
    slot_base      = { 100, 220, 120 },
    multi_drop     = { 180, 140, 255 },
    crit_mult      = { 255, 60, 160 },

    -- Tier 4
    extra_ball     = { 120, 255, 200 },
    sky_drop       = { 160, 170, 230 },
    heavy_landing  = { 220, 140, 60 },
    combo_storm    = { 255, 100, 200 },
    -- Tier 5
    slot_fortune   = { 255, 220, 100 },
    prestige_boost = { 60, 220, 200 },
    earning_amp    = { 255, 160, 40 },
}

--- 创建金币余额固定栏（不随列表滚动）
---@return table UI 面板
function P.CreateUpgradeHeader()
    local goldStr = State.FormatNumber(gameState.idleCoins)
    -- 背景图原图 430×96，圆心 (48,48)，圆直径≈图高
    -- 用 contain+left 让图按高度缩放后靠左显示
    local barH = 38
    -- contain 缩放后：图片宽 = barH * 430/96
    local imgW = math.floor(barH * 430 / 96)  -- ≈170px
    -- 圆形区域宽度 = barH（圆直径=图高）
    local circleW = barH
    local coinSize = barH * 0.52

    return UI.Panel {
        id = "idleUpgradeHeader",
        -- 限制容器宽度 = 缩放后的图片宽度，这样 fill 不会拉伸
        width = imgW,
        height = barH,
        marginTop = 6,
        marginLeft = 8,
        backgroundImage = "image/ui_currency_bar_20260518073701.png",
        backgroundFit = "fill",
        -- 用 flex 行布局放置内容
        flexDirection = "row",
        alignItems = "center",
        children = {
            -- 左侧圆形区域：金币图标
            UI.Panel {
                width = circleW, height = barH,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Panel {
                        width = coinSize, height = coinSize,
                        backgroundImage = "image/gold_coin.png",
                        backgroundFit = "contain",
                    },
                },
            },
            -- 金币数字
            UI.Label {
                text = goldStr,
                fontSize = 14,
                fontColor = { 255, 220, 60, 255 },
                marginLeft = 2,
            },
            -- 弹性间隔
            UI.Panel { flexGrow = 1 },
            -- 右侧提示
            UI.Label {
                text = "永久升级",
                fontSize = 8,
                fontColor = { 140, 150, 180, 140 },
                marginRight = 8,
            },
        },
    }
end

--- 创建升级列表面板
---@param cb table 回调表
---@return table UI 面板
function P.CreateUpgradeList(cb)
    local items = {}
    local playerLevel = gameState.idleMaxUnlockedLevel or 1

    -- 升级项（已解锁显示正常，未解锁显示锁定提示）
    for i, upgCfg in ipairs(Config.IDLE.UPGRADES) do
        local reqLv = upgCfg.unlockLevel or 1
        if playerLevel >= reqLv then
            table.insert(items, P.CreateUpgradeItem(cb, upgCfg, i))
        else
            table.insert(items, P.CreateLockedItem(upgCfg, reqLv))
        end
    end

    return UI.Panel {
        id = "idleUpgradeList",
        width = "100%",
        gap = 5,
        children = items,
    }
end

--- 创建锁定状态的升级项（预告下一个待解锁）
---@param upgCfg table
---@param reqLv number
---@return table
function P.CreateLockedItem(upgCfg, reqLv)
    local iconColor = ICON_COLORS[upgCfg.id] or { 180, 180, 180 }
    return UI.Panel {
        id = "idleUpg_locked_" .. upgCfg.id,
        width = "100%",
        flexDirection = "row",
        padding = { 8, 7, 8, 7 },
        backgroundImage = IMG.CARD,
        backgroundFit = "sliced",
        backgroundSlice = CARD_SLICE,
        imageTint = { 120, 120, 120, 200 },
        alignItems = "center", gap = 8,
        opacity = 0.6,
        children = {
            -- 锁图标
            UI.Panel {
                width = 32, height = 32,
                justifyContent = "center", alignItems = "center",
                borderRadius = 7,
                backgroundColor = { 40, 40, 55, 180 },
                borderColor = { 60, 60, 80, 120 },
                borderWidth = 1,
                children = {
                    UI.Label {
                        text = "🔒",
                        fontSize = 14,
                        textAlign = "center",
                    },
                },
            },
            -- 信息
            UI.Panel {
                flexGrow = 1, flexShrink = 1, gap = 1,
                justifyContent = "center",
                children = {
                    UI.Label {
                        text = string.format("通关阶段 %d 解锁", reqLv),
                        fontSize = 12,
                        fontColor = { 90, 100, 130, 200 },
                    },
                },
            },
            -- 右侧解锁提示
            UI.Panel {
                padding = { 6, 3, 6, 3 },
                borderRadius = 5,
                backgroundColor = { iconColor[1], iconColor[2], iconColor[3], 20 },
                children = {
                    UI.Label {
                        text = string.format("阶段%d", reqLv),
                        fontSize = 11,
                        fontColor = { iconColor[1], iconColor[2], iconColor[3], 160 },
                    },
                },
            },
        },
    }
end

--- 创建单个升级项
---@param cb table 回调表
---@param upgCfg table 升级配置
---@param index number 索引
---@return table UI 面板
function P.CreateUpgradeItem(cb, upgCfg, index)
    local level = GetLevel(upgCfg.id)
    local isMaxed = level >= upgCfg.maxLevel
    local cost = Config.GetUpgradeCost(upgCfg, level)
    local canAfford = not isMaxed and gameState.idleCoins >= cost

    local iconColor = ICON_COLORS[upgCfg.id] or { 180, 180, 180 }

    -- 背景图
    local cardImg = canAfford and IMG.CARD_HL or IMG.CARD
    local cardTint = canAfford
        and { iconColor[1], iconColor[2], iconColor[3], 200 }
        or nil

    -- 名字 + 等级
    local nameText = upgCfg.name
    local levelTag = isMaxed and "MAX" or ("Lv." .. level)

    -- 效果描述（显示当前实际效果值）
    local effectText = upgCfg.formatValue(level, upgCfg)

    -- 费用文本
    local costText
    if isMaxed then
        costText = "已满级"
    else
        costText = State.FormatNumber(cost)
    end

    return UI.Panel {
        id = "idleUpg_" .. upgCfg.id,
        width = "100%",
        flexDirection = "row",
        padding = { 8, 7, 8, 7 },
        backgroundImage = cardImg,
        backgroundFit = "sliced",
        backgroundSlice = CARD_SLICE,
        imageTint = cardTint,
        alignItems = "center", gap = 8,
        pointerEvents = "auto",
        onClick = function()
            if isMaxed then return end
            cb.PlayClickSfx()
            cb.PurchaseUpgrade(upgCfg.id)
        end,
        children = {
            -- 左侧图标
            UI.Panel {
                width = 32, height = 32,
                justifyContent = "center", alignItems = "center",
                borderRadius = 7,
                backgroundColor = { iconColor[1], iconColor[2], iconColor[3], 50 },
                borderColor = { iconColor[1], iconColor[2], iconColor[3], 80 },
                borderWidth = 1,
                pointerEvents = "none",
                children = {
                    UI.Label {
                        text = string.sub(upgCfg.name, 1, 6),
                        fontSize = 12,
                        fontColor = { iconColor[1], iconColor[2], iconColor[3], 255 },
                        textAlign = "center",
                    },
                },
            },
            -- 中部信息（名字 + 描述数值）
            UI.Panel {
                flexGrow = 1, flexShrink = 1, gap = 1, pointerEvents = "none",
                children = {
                    -- 第一行：名字 + 等级标签
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label {
                                text = nameText,
                                fontSize = 14,
                                fontColor = { 230, 240, 255, 255 },
                            },
                            UI.Panel {
                                padding = { 4, 1, 4, 1 },
                                borderRadius = 3,
                                backgroundColor = isMaxed
                                    and { 255, 200, 50, 40 }
                                    or { iconColor[1], iconColor[2], iconColor[3], 30 },
                                children = {
                                    UI.Label {
                                        text = levelTag,
                                        fontSize = 10,
                                        fontColor = isMaxed
                                            and { 255, 220, 80, 255 }
                                            or { iconColor[1], iconColor[2], iconColor[3], 220 },
                                    },
                                },
                            },
                        },
                    },
                    -- 第二行：描述 + 当前效果值（合并为一行）
                    UI.Label {
                        text = (upgCfg.desc or "") .. (effectText ~= "" and (" · " .. effectText) or ""),
                        fontSize = 11,
                        fontColor = { 160, 170, 190, 200 },
                    },
                },
            },
            -- 右侧升级按钮
            UI.Panel {
                minWidth = 52,
                padding = { 8, 5, 8, 5 },
                borderRadius = 6,
                backgroundColor = isMaxed
                    and { 50, 50, 40, 180 }
                    or (canAfford
                        and { 50, 130, 70, 230 }
                        or { 40, 42, 58, 200 }),
                borderColor = isMaxed
                    and { 80, 80, 60, 100 }
                    or (canAfford
                        and { 80, 200, 100, 150 }
                        or { 55, 60, 80, 100 }),
                borderWidth = 1,
                justifyContent = "center", alignItems = "center",
                pointerEvents = "none",
                children = {
                    -- 金币图标 + 费用
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 3,
                        children = isMaxed
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
                                    width = 14, height = 14, borderRadius = 7,
                                    backgroundImage = "image/gold_coin.png",
                                },
                                UI.Label {
                                    text = costText,
                                    fontSize = 12,
                                    fontColor = canAfford
                                        and { 255, 240, 180, 255 }
                                        or { 110, 115, 140, 180 },
                                    textAlign = "center",
                                },
                            },
                    },
                },
            },
        },
    }
end

return P
