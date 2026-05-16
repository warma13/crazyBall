-- ============================================================================
-- UI/EffectPanel.lua - 全局升级 + 抽取效果面板
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local State = require("State")
local Upgrades = require("Upgrades")
local Slots = require("Slots")
local Enchantment = require("Enchantment")

local gameState = State.gameState

local P = {}

--- 创建一键升级按钮
---@param cb table 回调表 { PlayClickSfx }
---@return table UI 面板
function P.CreateBulkUpgradeButton(cb)
    local isBalls = (gameState.activeTab == "balls")
    local label = isBalls and "一键升级钢珠" or "一键升级口袋"

    return UI.Panel {
        id = "bulkUpgradeBtn",
        width = "100%",
        flexDirection = "row",
        padding = { 8, 10, 8, 10 },
        backgroundColor = { 40, 70, 55, 240 },
        borderColor = { 80, 180, 100, 200 },
        borderWidth = 1.5, borderRadius = 10,
        alignItems = "center", justifyContent = "center",
        gap = 6,
        pointerEvents = "auto",
        onClick = function()
            cb.PlayClickSfx()
            if isBalls then
                Upgrades.BulkUpgradeBall()
            else
                Slots.BulkUpgradeSlots()
            end
        end,
        children = {
            UI.Label {
                text = label,
                fontSize = 16,
                fontColor = { 180, 255, 180, 255 },
                textAlign = "center",
            },
        }
    }
end

--- 创建附魔按钮（钢珠 tab 右侧 20% 宽）
---@param cb table 回调表 { PlayClickSfx, ADS_ENABLED }
---@return table UI 面板
function P.CreateEnchantButton(cb)
    local ballIndex = gameState.selectedBallType
    local level = gameState.ballLevels[ballIndex]
    local isUnlocked = level > 0
    local count = Enchantment.GetCount(ballIndex)
    local totalLv = Enchantment.GetTotalLevel(ballIndex)

    local label, bgColor, borderC
    if not isUnlocked then
        label = "附魔"
        bgColor = { 40, 40, 50, 200 }
        borderC = { 60, 60, 80, 150 }
    elseif count > 0 then
        label = "附魔×" .. totalLv
        bgColor = { 80, 50, 120, 220 }
        borderC = { 180, 130, 255, 220 }
    else
        label = "附魔"
        bgColor = { 60, 40, 80, 220 }
        borderC = { 160, 120, 220, 200 }
    end

    return UI.Panel {
        id = "enchantBtn",
        width = "20%",
        padding = { 8, 6, 8, 6 },
        backgroundColor = bgColor,
        borderColor = borderC,
        borderWidth = 1.5, borderRadius = 10,
        alignItems = "center", justifyContent = "center",
        gap = 2,
        pointerEvents = "auto",
        onClick = function()
            cb.PlayClickSfx()
            if not isUnlocked then return end
            if not cb.ADS_ENABLED then return end
            Enchantment.AdEnchant()
        end,
        children = {
            UI.Panel {
                width = 28, height = 28,
                backgroundImage = "image/icon_ad.png",
                backgroundSize = "contain",
                pointerEvents = "none",
            },
            UI.Label {
                text = label,
                fontSize = 11,
                fontColor = count > 0 and { 220, 180, 255, 255 } or { 180, 160, 220, 220 },
                textAlign = "center",
                pointerEvents = "none",
            },
        }
    }
end

--- 创建抽取效果按钮
---@param cb table 回调表 { PlayClickSfx, ADS_ENABLED }
---@return table UI 面板
function P.CreateDrawButton(cb)
    local ownedCount = Upgrades.GetNormalPoolOwned()
    local totalCount = Upgrades.GetNormalPoolTotal()
    local allDrawn = (ownedCount >= totalCount)

    local cost = Upgrades.GetDrawCost()
    local canAfford = State.GetGems() >= cost
    local remaining = totalCount - ownedCount

    local costText = State.FormatNumber(cost)
    local statusText = allDrawn
        and (totalCount .. "/" .. totalCount .. " 全部收集")
        or (remaining .. " 个效果待解锁")

    local accentColor, bgColor, borderW
    if allDrawn then
        accentColor = { 80, 90, 110, 180 }
        bgColor = { 30, 35, 55, 200 }
        borderW = 1.5
    elseif canAfford then
        accentColor = { 255, 200, 60, 255 }
        bgColor = { 70, 55, 15, 245 }
        borderW = 2.5
    else
        accentColor = { 100, 80, 50, 180 }
        bgColor = { 45, 35, 20, 230 }
        borderW = 1.5
    end
    local iconBg = allDrawn
        and { 60, 65, 80, 200 }
        or (canAfford and { 255, 180, 30, 240 } or { 180, 120, 30, 220 })

    -- 广告抽取小按钮（内嵌）
    local adPool = Upgrades.BuildAdPool()
    local hasAdPool = cb.ADS_ENABLED and (#adPool > 0)
    local adBtnWidget = nil
    if hasAdPool then
        adBtnWidget = UI.Panel {
            flexDirection = "row",
            padding = { 5, 4, 5, 4 },
            borderRadius = 6,
            alignItems = "center", gap = 3,
            backgroundColor = { 200, 60, 40, 240 },
            pointerEvents = "auto",
            onClick = function()
                cb.PlayClickSfx()
                Upgrades.OnAdDrawEffect()
            end,
            children = {
                UI.Panel {
                    width = 20, height = 20,
                    backgroundImage = "image/icon_legendary.png",
                    backgroundSize = "contain",
                },
                UI.Label {
                    text = "传说×" .. #adPool,
                    fontSize = 13,
                    fontColor = { 255, 220, 200, 255 },
                },
            },
        }
    end

    -- 右侧按钮组
    local rightChildren = {}
    if adBtnWidget then
        table.insert(rightChildren, adBtnWidget)
    end
    -- 宝石不足时显示广告抽取按钮（普通池）
    if cb.ADS_ENABLED and not allDrawn and not canAfford and remaining > 0 then
        table.insert(rightChildren, UI.Panel {
            flexDirection = "row",
            padding = { 5, 4, 5, 4 },
            borderRadius = 6,
            alignItems = "center", gap = 3,
            backgroundColor = { 200, 60, 40, 240 },
            pointerEvents = "auto",
            onClick = function()
                cb.PlayClickSfx()
                Upgrades.AdDrawEffect()
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
    end
    table.insert(rightChildren, UI.Panel {
        flexDirection = "row",
        padding = { 5, 4, 5, 4 },
        borderRadius = 6,
        alignItems = "center", gap = 3,
        backgroundColor = allDrawn and { 40, 45, 55, 200 }
            or (canAfford and { 220, 160, 30, 240 } or { 60, 45, 20, 230 }),
        pointerEvents = "none",
        children = allDrawn
            and {
                UI.Label {
                    text = "已集齐",
                    fontSize = 13,
                    fontColor = { 100, 110, 130, 180 },
                },
            }
            or {
                UI.Panel {
                    width = 12, height = 12,
                    backgroundImage = "image/gem_20260328213704.png",
                },
                UI.Label {
                    text = costText,
                    fontSize = 13,
                    fontColor = canAfford
                        and { 255, 255, 220, 255 }
                        or { 255, 220, 100, 255 },
                },
            },
    })

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        padding = { 8, 10, 8, 10 },
        backgroundColor = bgColor,
        borderColor = accentColor,
        borderWidth = borderW, borderRadius = 10,
        alignItems = "center", gap = 10,
        pointerEvents = "auto",
        onClick = function()
            cb.PlayClickSfx()
            if allDrawn then return end
            local drawn = Upgrades.OnDrawEffect()
            if not drawn then return end
        end,
        children = {
            UI.Panel {
                width = 24, height = 24, borderRadius = 12,
                backgroundColor = iconBg,
                justifyContent = "center", alignItems = "center",
                pointerEvents = "none",
                children = {
                    UI.Label {
                        text = "?",
                        fontSize = 17,
                        fontColor = { 255, 255, 255, 240 },
                        textAlign = "center",
                    },
                }
            },
            UI.Panel {
                flexGrow = 1, gap = 1, pointerEvents = "none",
                children = {
                    UI.Label {
                        text = "抽取效果",
                        fontSize = 16,
                        fontColor = allDrawn
                            and { 120, 130, 150, 200 }
                            or { 255, 220, 120, 255 },
                    },
                    UI.Label {
                        text = statusText,
                        fontSize = 13,
                        fontColor = { 140, 150, 180, 180 },
                    },
                }
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center", gap = 6,
                children = rightChildren,
            },
        }
    }
end

--- 创建单个效果升级项
---@param cb table 回调表 { PlayClickSfx, ADS_ENABLED }
---@param eff table 效果配置
---@return table UI 面板
function P.CreateEffectItem(cb, eff)
    local level = Upgrades.GetEffectLevel(eff.id)
    local value = eff.valueFunc(level)
    local desc = eff.descFunc(level, value)
    local upgradeCost = Upgrades.GetEffectUpgradeCost(eff.id)
    local canAfford = upgradeCost ~= nil and State.GetGems() >= upgradeCost
    local costText2 = upgradeCost and State.FormatNumber(upgradeCost) or "--"

    -- 品质标识 + 球型专属标签
    local qualityTier = Config.GetQualityTier(eff.quality or "common")
    local nameText = eff.name
    if eff.ballType then
        nameText = nameText .. " ★"
    end

    -- 右侧按钮组
    local rightChildren = {}
    if cb.ADS_ENABLED and not canAfford then
        table.insert(rightChildren, UI.Panel {
            flexDirection = "row",
            padding = { 5, 3, 5, 3 },
            borderRadius = 5,
            alignItems = "center", gap = 3,
            backgroundColor = { 200, 60, 40, 240 },
            pointerEvents = "auto",
            onClick = function(self)
                cb.PlayClickSfx()
                Upgrades.AdUpgradeEffect(eff.id)
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
    end
    table.insert(rightChildren, UI.Panel {
        flexDirection = "row",
        padding = { 5, 4, 5, 4 },
        borderRadius = 6,
        alignItems = "center", gap = 3,
        backgroundColor = canAfford and { 60, 140, 80, 220 } or { eff.color[1], eff.color[2], eff.color[3], 40 },
        pointerEvents = "none",
        children = {
            UI.Panel {
                width = 11, height = 11,
                backgroundImage = "image/gem_20260328213704.png",
            },
            UI.Label {
                text = costText2,
                fontSize = 12,
                fontColor = canAfford
                    and { 180, 255, 180, 255 }
                    or { eff.color[1], eff.color[2], eff.color[3], 150 },
            },
        }
    })

    return UI.Panel {
        id = "eff_" .. eff.id,
        width = "100%",
        flexDirection = "row",
        padding = { 6, 8, 6, 8 },
        backgroundColor = { eff.color[1], eff.color[2], eff.color[3], 25 },
        borderColor = canAfford
            and { eff.color[1], eff.color[2], eff.color[3], 200 }
            or { eff.color[1], eff.color[2], eff.color[3], 60 },
        borderWidth = canAfford and 1.5 or 1, borderRadius = 8,
        alignItems = "center", gap = 8,
        pointerEvents = "auto",
        onClick = function()
            cb.PlayClickSfx()
            Upgrades.OnUpgradeEffect(eff.id)
        end,
        children = {
            UI.Panel {
                width = 20, height = 20, borderRadius = 10,
                backgroundColor = { qualityTier.color[1], qualityTier.color[2], qualityTier.color[3], 200 },
                justifyContent = "center", alignItems = "center",
                pointerEvents = "none",
                children = {
                    UI.Label {
                        text = tostring(level),
                        fontSize = 12,
                        fontColor = { 255, 255, 255, 240 },
                        textAlign = "center",
                    },
                }
            },
            UI.Panel {
                flexGrow = 1, gap = 1, pointerEvents = "none",
                children = {
                    UI.Label {
                        text = "[" .. qualityTier.name .. "] " .. nameText .. "  Lv." .. level,
                        fontSize = 15,
                        fontColor = { qualityTier.color[1], qualityTier.color[2], qualityTier.color[3], 255 },
                    },
                    UI.Label {
                        text = desc,
                        fontSize = 12,
                        fontColor = { 140, 150, 180, 180 },
                    },
                }
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center", gap = 4,
                children = rightChildren,
            },
        }
    }
end

--- 创建全局升级列表（按品质分组）
---@param cb table 回调表
---@return table UI 面板
function P.CreateGlobalUpgradeRow(cb)
    local children = {}

    -- 按品质分组（高→低）
    for _, qualityId in ipairs(Config.QUALITY_ORDER) do
        local tier = Config.GetQualityTier(qualityId)
        local groupEffects = {}
        for _, eff in ipairs(Config.DRAW_EFFECTS) do
            if (eff.quality or "common") == qualityId and Upgrades.HasEffect(eff.id) then
                table.insert(groupEffects, eff)
            end
        end

        if #groupEffects > 0 then
            -- 品质分隔标题
            table.insert(children, UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                padding = { 2, 6, 2, 6 },
                gap = 6,
                children = {
                    UI.Panel {
                        width = 8, height = 8, borderRadius = 4,
                        backgroundColor = tier.color,
                        pointerEvents = "none",
                    },
                    UI.Label {
                        text = tier.name .. " (" .. #groupEffects .. ")",
                        fontSize = 14,
                        fontColor = { tier.color[1], tier.color[2], tier.color[3], 200 },
                    },
                    UI.Panel {
                        flexGrow = 1, height = 1,
                        backgroundColor = { tier.color[1], tier.color[2], tier.color[3], 60 },
                        pointerEvents = "none",
                    },
                }
            })
            -- 该品质下所有已拥有效果
            for _, eff in ipairs(groupEffects) do
                table.insert(children, P.CreateEffectItem(cb, eff))
            end
        end
    end

    return UI.Panel {
        id = "effectList",
        width = "100%",
        gap = 5,
        children = children,
    }
end

return P
