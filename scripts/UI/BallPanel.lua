-- ============================================================================
-- UI/BallPanel.lua - 钢珠选择面板
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local BigNum = require("BigNum")
local State = require("State")
local Upgrades = require("Upgrades")
local Enchantment = require("Enchantment")

local gameState = State.gameState

local P = {}

-- 卡片图片资源（九宫格切图，复用放置模式图片）
local IMG_CARD_NORMAL    = "image/ui_card_normal_20260517160219.png"
local IMG_CARD_HIGHLIGHT = "image/ui_card_highlight_20260517160012.png"
local CARD_SLICE = { top = 16, right = 16, bottom = 16, left = 16 }

--- 创建钢珠列表
---@param cb table 回调表
---@return table UI 面板
function P.CreateBallSelectionRow(cb)
    local ballBtns = {}
    for i = 1, #Config.BALL_TYPES do
        table.insert(ballBtns, P.CreateBallButton(cb, i))
    end
    return UI.Panel {
        id = "ballList",
        width = "100%",
        gap = 5,
        children = ballBtns,
    }
end

--- 创建单个钢珠按钮
---@param cb table 回调表 { PlayClickSfx, ADS_ENABLED, ShowSkinPanel }
---@param index number 球索引
---@return table UI 面板
function P.CreateBallButton(cb, index)
    local bt = Config.BALL_TYPES[index]
    local level = gameState.ballLevels[index]
    local isUnlocked = level > 0
    local isSelected = (index == gameState.selectedBallType)

    local cardImg = IMG_CARD_HIGHLIGHT

    local infoText, actionText, actionCost
    if not isUnlocked then
        infoText = "价值 " .. bt.baseValue
        actionCost = bt.cost
        actionText = "解锁 " .. State.FormatNumber(bt.cost)
    else
        local value = BigNum.new(bt.baseValue) * level
        infoText = "Lv." .. level .. "  价值 " .. State.FormatNumber(value)
        actionCost = Upgrades.GetBallUpgradeCost(index)
        actionText = "升级 " .. State.FormatNumber(actionCost)
    end

    local canAfford = gameState.coins >= actionCost

    -- 广告按钮：资源不足时显示（隐藏占位，不移除）
    local prevUnlocked = index <= 1 or gameState.ballLevels[index - 1] > 0
    local canShowAd = not canAfford

    -- 所有卡片统一使用高亮图片，不能操作时通过 opacity 变暗

    -- 右侧按钮组
    local rightChildren = {}
    -- 广告按钮：仅选中球且买不起时显示，其余隐藏占位
    local adVisible = cb.ADS_ENABLED and isSelected and canShowAd
    table.insert(rightChildren, UI.Panel {
        id = "adBtn_" .. index,
        flexDirection = "row",
        padding = { 5, 4, 5, 4 },
        borderRadius = 6,
        alignItems = "center", gap = 3,
        backgroundColor = { 200, 60, 40, 240 },
        pointerEvents = adVisible and "auto" or "none",
        opacity = adVisible and 1.0 or 0.0,

        onClick = function(self)
            cb.PlayClickSfx()
            Upgrades.AdBallUpgrade(index)
        end,
        children = {
            UI.Panel {
                width = 20, height = 20,
                backgroundImage = "image/icon_ad.png",
                backgroundSize = "contain",
            },
            UI.Label {
                text = "广告",
                fontSize = 12,
                fontColor = { 255, 255, 255, 240 },
            },
        },
    })
    table.insert(rightChildren, UI.Panel {
        id = "costBtn_" .. index,
        padding = { 5, 4, 5, 4 },
        borderRadius = 6,
        backgroundColor = (isSelected and canAfford) and { 60, 140, 80, 220 }
            or (not isUnlocked and canAfford) and { 220, 160, 30, 240 }
            or (canAfford and { 50, 70, 90, 200 } or { 40, 45, 65, 200 }),
        pointerEvents = "none",
        children = {
            UI.Label {
                id = "costLabel_" .. index,
                text = not isUnlocked and (State.FormatNumber(bt.cost) .. " 金币")
                    or actionText,
                fontSize = 13,
                fontColor = (isSelected and canAfford)
                    and { 180, 255, 180, 255 }
                    or (not isUnlocked and canAfford)
                        and { 255, 255, 220, 255 }
                    or (canAfford
                        and { 180, 200, 230, 255 }
                        or { 120, 130, 160, 180 }),
                textAlign = "center",
            },
        }
    })

    local cardBright = canAfford

    return UI.Panel {
        id = "ball_" .. index,
        width = "100%",
        flexDirection = "row",
        padding = { 10, 10, 10, 10 },
        backgroundImage = cardImg,
        backgroundFit = "sliced",
        backgroundSlice = CARD_SLICE,
        opacity = cardBright and 1.0 or 0.55,
        alignItems = "center", gap = 10,
        pointerEvents = "auto",
        onClick = function() cb.PlayClickSfx(); Upgrades.OnBallButtonClick(index) end,
        children = {
            UI.Panel {
                width = 30, height = 30,
                backgroundImage = Config.GetBallSkinImage(bt.skinKey),
                backgroundSize = "contain",
                opacity = isUnlocked and 1.0 or 0.5,
            },
            UI.Panel {
                flexGrow = 1, flexShrink = 1, gap = 1, pointerEvents = "none",
                children = (function()
                    local labels = {
                        UI.Label {
                            id = "ballTitle_" .. index,
                            text = isUnlocked and (bt.name .. "  Lv." .. level) or bt.name,
                            fontSize = 16,
                            fontColor = isUnlocked and { 230, 240, 255, 255 } or { 120, 130, 150, 200 },
                        },
                        UI.Label {
                            id = "ballInfo_" .. index,
                            text = infoText,
                            fontSize = 13,
                            fontColor = { 140, 160, 200, 180 },
                        },
                    }
                    -- 显示特殊效果描述
                    if bt.effect then
                        local effColor = isUnlocked
                            and { bt.color[1], bt.color[2], bt.color[3], 200 }
                            or { 100, 110, 130, 150 }
                        table.insert(labels, UI.Label {
                            text = bt.effect.name .. ": " .. bt.effect.desc,
                            fontSize = 12,
                            fontColor = effColor,
                        })
                    end
                    -- 显示附魔指示器
                    if isUnlocked then
                        local enchants = Enchantment.GetAll(index)
                        local enchantIcons = {}
                        for _, cfg in ipairs(Config.ENCHANTMENTS) do
                            local lv = enchants[cfg.id]
                            if lv and lv > 0 then
                                table.insert(enchantIcons, UI.Panel {
                                    flexDirection = "row",
                                    alignItems = "center",
                                    gap = 1,
                                    children = {
                                        UI.Panel {
                                            width = 14, height = 14,
                                            backgroundImage = cfg.iconImage,
                                            backgroundFit = "contain",
                                        },
                                        UI.Label {
                                            text = tostring(lv),
                                            fontSize = 11,
                                            fontColor = { cfg.color[1], cfg.color[2], cfg.color[3], 220 },
                                        },
                                    },
                                })
                            end
                        end
                        if #enchantIcons > 0 then
                            table.insert(labels, UI.Panel {
                                flexDirection = "row",
                                gap = 6,
                                marginTop = 1,
                                children = enchantIcons,
                            })
                        end
                    end
                    return labels
                end)(),
            },
            UI.Panel {
                flexShrink = 0,
                flexDirection = "row",
                alignItems = "center", gap = 4,
                children = rightChildren,
            },
        }
    }
end

--- 就地更新单个球卡片的等级文本 + affordability 样式（不重建 DOM）
--- 适用于升级/解锁后的轻量刷新，避免 remove+insert 导致的高度闪烁
---@param cb table 回调表
---@param index number 球索引
---@return boolean 是否成功
function P.UpdateBallLevel(cb, index)
    local root = State.uiRoot_
    if not root then return false end

    local card = root:FindById("ball_" .. index)
    if not card then return false end

    local bt = Config.BALL_TYPES[index]
    local level = gameState.ballLevels[index]
    local isUnlocked = level > 0
    local isSelected = (index == gameState.selectedBallType)

    -- 1) 标题文本 + 颜色
    local titleLabel = root:FindById("ballTitle_" .. index)
    if titleLabel then
        titleLabel:SetStyle({
            text = isUnlocked and (bt.name .. "  Lv." .. level) or bt.name,
            fontColor = isUnlocked and { 230, 240, 255, 255 } or { 120, 130, 150, 200 },
        })
    end

    -- 2) 信息文本
    local infoLabel = root:FindById("ballInfo_" .. index)
    if infoLabel then
        local infoText
        if not isUnlocked then
            infoText = "价值 " .. bt.baseValue
        else
            local value = BigNum.new(bt.baseValue) * level
            infoText = "Lv." .. level .. "  价值 " .. State.FormatNumber(value)
        end
        infoLabel:SetStyle({ text = infoText })
    end

    -- 3) 费用文本
    local actionCost
    if not isUnlocked then
        actionCost = bt.cost
    else
        actionCost = Upgrades.GetBallUpgradeCost(index)
    end

    local costLabel = root:FindById("costLabel_" .. index)
    if costLabel then
        local actionText
        if not isUnlocked then
            actionText = State.FormatNumber(bt.cost) .. " 金币"
        else
            actionText = "升级 " .. State.FormatNumber(actionCost)
        end
        costLabel:SetStyle({ text = actionText })
    end

    -- 4) affordability 样式（复用 UpdateAffordability 逻辑）
    local canAfford = gameState.coins >= actionCost
    local adVisible = cb.ADS_ENABLED and isSelected and (not canAfford)

    card:SetStyle({ opacity = canAfford and 1.0 or 0.55 })

    local adBtn = root:FindById("adBtn_" .. index)
    if adBtn then
        adBtn:SetStyle({
            opacity = adVisible and 1.0 or 0.0,
            pointerEvents = adVisible and "auto" or "none",
        })
    end

    local costBtn = root:FindById("costBtn_" .. index)
    if costBtn then
        costBtn:SetStyle({
            backgroundColor = (isSelected and canAfford) and { 60, 140, 80, 220 }
                or (not isUnlocked and canAfford) and { 220, 160, 30, 240 }
                or (canAfford and { 50, 70, 90, 200 } or { 40, 45, 65, 200 }),
        })
    end

    if costLabel then
        costLabel:SetStyle({
            fontColor = (isSelected and canAfford)
                and { 180, 255, 180, 255 }
                or (not isUnlocked and canAfford)
                    and { 255, 255, 220, 255 }
                or (canAfford
                    and { 180, 200, 230, 255 }
                    or { 120, 130, 160, 180 }),
        })
    end

    return true
end

--- 就地更新单个球卡片的 affordability 样式（不重建 DOM）
---@param cb table 回调表
---@param index number 球索引
---@return boolean 是否成功
function P.UpdateAffordability(cb, index)
    local root = State.uiRoot_
    if not root then return false end

    local card = root:FindById("ball_" .. index)
    if not card then return false end

    local bt = Config.BALL_TYPES[index]
    local level = gameState.ballLevels[index]
    local isUnlocked = level > 0
    local isSelected = (index == gameState.selectedBallType)

    local actionCost
    if not isUnlocked then
        actionCost = bt.cost
    else
        actionCost = Upgrades.GetBallUpgradeCost(index)
    end

    local canAfford = gameState.coins >= actionCost
    local adVisible = cb.ADS_ENABLED and isSelected and (not canAfford)

    -- 卡片整体明暗
    card:SetStyle({ opacity = canAfford and 1.0 or 0.55 })

    -- 广告按钮显隐
    local adBtn = root:FindById("adBtn_" .. index)
    if adBtn then
        adBtn:SetStyle({
            opacity = adVisible and 1.0 or 0.0,
            pointerEvents = adVisible and "auto" or "none",
        })
    end

    -- 费用按钮背景色
    local costBtn = root:FindById("costBtn_" .. index)
    if costBtn then
        costBtn:SetStyle({
            backgroundColor = (isSelected and canAfford) and { 60, 140, 80, 220 }
                or (not isUnlocked and canAfford) and { 220, 160, 30, 240 }
                or (canAfford and { 50, 70, 90, 200 } or { 40, 45, 65, 200 }),
        })
    end

    -- 费用文字颜色
    local costLabel = root:FindById("costLabel_" .. index)
    if costLabel then
        costLabel:SetStyle({
            fontColor = (isSelected and canAfford)
                and { 180, 255, 180, 255 }
                or (not isUnlocked and canAfford)
                    and { 255, 255, 220, 255 }
                or (canAfford
                    and { 180, 200, 230, 255 }
                    or { 120, 130, 160, 180 }),
        })
    end

    return true
end

return P
