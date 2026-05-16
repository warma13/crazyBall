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

    local bgColor = isSelected
        and { bt.color[1], bt.color[2], bt.color[3], 60 }
        or { 30, 35, 55, 200 }

    local borderColor = isSelected
        and { bt.color[1], bt.color[2], bt.color[3], 200 }
        or { 50, 60, 80, 150 }

    local isAdOnly = bt.adOnly and not isUnlocked  -- 广告专属解锁球（未解锁时生效）

    local infoText, actionText, actionCost
    if not isUnlocked then
        infoText = "价值 " .. bt.baseValue
        actionCost = bt.cost
        actionText = "解锁 " .. State.FormatNumber(bt.cost)
    else
        local milestones = math.floor(level / 10)
        local milestoneMult = (milestones > 0) and (BigNum.new(2) ^ milestones) or BigNum.new(1)
        local value = BigNum.new(bt.baseValue) * milestoneMult * level
        local nextMilestone = (milestones + 1) * 10
        local progress = level % 10
        infoText = "价值 " .. State.FormatNumber(value)
            .. "  ★" .. milestones .. " (" .. progress .. "/10)"
        actionCost = Upgrades.GetBallUpgradeCost(index)
        actionText = "升级 " .. State.FormatNumber(actionCost)
    end

    local canAfford = (not isAdOnly) and (gameState.coins >= actionCost)

    -- 广告按钮：adOnly球始终显示广告，普通球资源不足时显示
    local prevUnlocked = index <= 1 or gameState.ballLevels[index - 1] > 0
    local canShowAd
    if not isUnlocked and not prevUnlocked then
        canShowAd = false  -- 前一个球未解锁，不允许广告解锁
    elseif isAdOnly then
        canShowAd = true   -- 广告专属球始终显示广告按钮
    else
        canShowAd = not canAfford
    end

    if isSelected then
        borderColor = canAfford
            and { bt.color[1], bt.color[2], bt.color[3], 240 }
            or { bt.color[1], bt.color[2], bt.color[3], 100 }
    elseif not isUnlocked and (canAfford or canShowAd) then
        borderColor = canAfford and { 255, 200, 60, 180 } or { 200, 80, 60, 150 }
    end

    -- 右侧按钮组
    local rightChildren = {}
    if cb.ADS_ENABLED and canShowAd then
        table.insert(rightChildren, UI.Panel {
            flexDirection = "row",
            padding = { 5, 4, 5, 4 },
            borderRadius = 6,
            alignItems = "center", gap = 3,
            backgroundColor = isAdOnly and { 220, 140, 30, 240 } or { 200, 60, 40, 240 },
            pointerEvents = "auto",
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
                    text = isAdOnly and "广告解锁" or "广告",
                    fontSize = 12,
                    fontColor = { 255, 255, 255, 240 },
                },
            },
        })
    end
    -- adOnly球未解锁时不显示金币按钮
    if not isAdOnly then
        table.insert(rightChildren, UI.Panel {
            padding = { 5, 4, 5, 4 },
            borderRadius = 6,
            backgroundColor = (isSelected and canAfford) and { 60, 140, 80, 220 }
                or (not isUnlocked and canAfford) and { 220, 160, 30, 240 }
                or (canAfford and { 50, 70, 90, 200 } or { 40, 45, 65, 200 }),
            pointerEvents = "none",
            children = {
                UI.Label {
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
    end

    return UI.Panel {
        id = "ball_" .. index,
        width = "100%",
        flexDirection = "row",
        padding = { 8, 8, 8, 8 },
        backgroundColor = bgColor,
        borderColor = borderColor,
        borderWidth = (isSelected and canAfford) and 2 or 1.5, borderRadius = 10,
        alignItems = "center", gap = 10,
        pointerEvents = "auto",
        onClick = function() cb.PlayClickSfx(); Upgrades.OnBallButtonClick(index) end,
        children = {
            (function()
                local activeSkin = gameState.ballSkins[index] or "default"
                local hasSkinImage = (activeSkin ~= "default")
                if isUnlocked and hasSkinImage then
                    -- 已解锁且选了图片皮肤：直接显示图片，无圆形容器
                    return UI.Panel {
                        width = 30, height = 30,
                        backgroundImage = Config.GetBallSkinImage(bt.skinKey),
                        backgroundSize = "contain",
                        pointerEvents = "auto",
                        onClick = function(self)
                            cb.PlayClickSfx()
                            cb.ShowSkinPanel(index)
                        end,
                    }
                else
                    -- 默认皮肤：彩色圆圈
                    return UI.Panel {
                        width = 30, height = 30,
                        justifyContent = "center", alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function(self)
                            if isUnlocked then
                                cb.PlayClickSfx()
                                cb.ShowSkinPanel(index)
                            end
                        end,
                        children = {
                            UI.Panel {
                                width = isUnlocked and 22 or 16,
                                height = isUnlocked and 22 or 16,
                                borderRadius = isUnlocked and 11 or 8,
                                backgroundColor = isUnlocked and bt.color or { 80, 80, 80, 200 },
                                pointerEvents = "none",
                            },
                        },
                    }
                end
            end)(),
            UI.Panel {
                flexGrow = 1, gap = 1, pointerEvents = "none",
                children = (function()
                    local labels = {
                        UI.Label {
                            text = isUnlocked and (bt.name .. "  Lv." .. level) or bt.name,
                            fontSize = 16,
                            fontColor = isUnlocked and { 230, 240, 255, 255 } or { 120, 130, 150, 200 },
                        },
                        UI.Label {
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
                                table.insert(enchantIcons, UI.Label {
                                    text = cfg.icon .. lv,
                                    fontSize = 11,
                                    fontColor = { cfg.color[1], cfg.color[2], cfg.color[3], 220 },
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
                flexDirection = "row",
                alignItems = "center", gap = 4,
                children = rightChildren,
            },
        }
    }
end

return P
