-- ============================================================================
-- UI/IdleBallPanel.lua - 放置模式弹珠面板（当前弹珠信息 + 能力升级）
-- 每关固定一种弹珠（关卡1=铁球, 关卡2=铜球, ...），不再选择/解锁弹珠
-- 下方展示弹珠能力升级列表（球币购买）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local State = require("State")
local Enchantment = require("Enchantment")

local gameState = State.gameState

local P = {}

-- UI 背景图路径
local IMG = {
    CARD       = "image/ui_card_normal_20260517160219.png",
    CARD_HL    = "image/ui_card_highlight_20260517160012.png",
}
local CARD_SLICE = { top = 20, right = 20, bottom = 20, left = 20 }

-- 当前选中查看的附魔索引（1-based，对应 Config.ENCHANTMENTS）
local selectedEnchantIdx = 1

-- ======= 轻量更新引用 =======
-- { [abilityId] = { card=widget, btn=widget, costLbl=widget, lastCanAfford=bool } }
local abilityRefs = {}
local headerCoinRef = nil  -- header 中的球币 Label

--- 创建球币余额固定栏（不随列表滚动）
---@return table UI 面板
function P.CreateBallHeader()
    local IdleMode = require("IdleMode")
    local typeIdx = IdleMode.GetCurrentBallType()
    local bt = Config.BALL_TYPES[typeIdx]
    local bc = bt and bt.color or { 100, 180, 255 }
    local skinImg = Config.GetBallSkinImage(bt and bt.skinKey or "iron")
    local ballCoinStr = State.FormatNumber(gameState.idleBallCoins)

    -- 与金币栏相同的背景图样式（430×96）
    local barH = 38
    local imgW = math.floor(barH * 430 / 96)
    local circleW = barH
    local iconSize = barH * 0.52

    return UI.Panel {
        id = "idleBallHeader",
        width = imgW,
        height = barH,
        marginTop = 6,
        marginLeft = 8,
        backgroundImage = "image/ui_currency_bar_20260518073701.png",
        backgroundFit = "fill",
        flexDirection = "row",
        alignItems = "center",
        children = {
            -- 左侧圆形区域：弹珠图标
            UI.Panel {
                width = circleW, height = barH,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Panel {
                        width = iconSize, height = iconSize,
                        backgroundImage = skinImg,
                        backgroundFit = "contain",
                    },
                },
            },
            -- 球币数字
            UI.Label {
                id = "ballCoinLabel",
                text = ballCoinStr,
                fontSize = 14,
                fontColor = { bc[1], bc[2], bc[3], 255 },
                marginLeft = 2,
            },
            UI.Panel { flexGrow = 1 },
            -- 右侧提示
            UI.Label {
                text = "转生清零",
                fontSize = 8,
                fontColor = { 140, 150, 180, 140 },
                marginRight = 8,
            },
        },
    }
end

--- 清空轻量更新引用（全量重建前调用）
function P.ResetRefs()
    abilityRefs = {}
    headerCoinRef = nil
end

--- 创建弹珠面板（当前弹珠信息 + 能力升级列表）
---@param cb table 回调表
---@return table UI 面板
function P.CreateBallList(cb)
    P.ResetRefs()
    local children = {}

    -- 顶部：当前弹珠信息卡片
    children[#children + 1] = P.CreateCurrentBallInfo(cb)

    -- 分隔标题
    children[#children + 1] = UI.Panel {
        width = "100%",
        paddingTop = 6, paddingBottom = 4,
        children = {
            UI.Label {
                text = "弹珠能力升级",
                fontSize = 15,
                fontColor = { 160, 180, 220, 220 },
            },
        },
    }

    -- 能力升级列表（按当前球类型动态获取）
    local IdleMode = require("IdleMode")
    local ballUpgrades = IdleMode.GetCurrentBallUpgrades()
    for i = 1, #ballUpgrades do
        children[#children + 1] = P.CreateAbilityItem(cb, i, ballUpgrades)
    end

    return UI.Panel {
        id = "idleBallList",
        width = "100%",
        gap = 5,
        children = children,
    }
end

--- 创建当前弹珠信息卡片
---@param cb table 回调表
---@return table UI 面板
function P.CreateCurrentBallInfo(cb)
    local IdleMode = require("IdleMode")
    local typeIdx = IdleMode.GetCurrentBallType()
    local bt = Config.BALL_TYPES[typeIdx]
    if not bt then
        return UI.Panel { width = "100%" }
    end

    -- 计算弹珠属性
    local baseVal = IdleMode.GetBaseBallValue() + IdleMode.GetBallValueBonus()
    local mult = IdleMode.GetBallMultiplier()
    local totalValue = math.floor(baseVal * mult * gameState.idlePrestigeMult)

    return UI.Panel {
        id = "idleBallInfo",
        width = "100%",
        padding = { 12, 10, 12, 10 },
        backgroundImage = IMG.CARD_HL,
        backgroundFit = "sliced",
        backgroundSlice = CARD_SLICE,
        imageTint = { bt.color[1], bt.color[2], bt.color[3], 200 },
        borderRadius = 12,
        gap = 6,
        children = {
            -- 顶行：弹珠名 + 圆点
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 10,
                children = {
                    -- 弹珠颜色圆
                    UI.Panel {
                        width = 28, height = 28,
                        borderRadius = 14,
                        backgroundColor = bt.color,
                    },
                    -- 名称 + 特性描述
                    UI.Panel {
                        flexGrow = 1, gap = 1,
                        children = {
                            UI.Label {
                                text = bt.name,
                                fontSize = 20,
                                fontColor = { 240, 245, 255, 255 },
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = bt.effect and (bt.effect.name .. ": " .. bt.effect.desc) or "",
                                fontSize = 12,
                                fontColor = { bt.color[1], bt.color[2], bt.color[3], 200 },
                            },
                        },
                    },
                },
            },
            -- 属性行（通用: 价值+倍率 + 专属升级摘要）
            P._CreateStatsRow(IdleMode, totalValue, mult, bt),
            -- 附魔栏
            P._CreateEnchantRow(cb, typeIdx),
        },
    }
end

--- 创建附魔栏（图标行 + 效果描述行）
---@param cb table 回调表
---@param ballIndex number 球索引
function P._CreateEnchantRow(cb, ballIndex)
    local enchants = Enchantment.GetAll(ballIndex)
    local pool = Config.ENCHANTMENTS

    -- 确保 selectedEnchantIdx 合法
    if selectedEnchantIdx < 1 or selectedEnchantIdx > #pool then
        selectedEnchantIdx = 1
    end

    -- 图标行
    local iconChildren = {}
    for i, cfg in ipairs(pool) do
        local lv = enchants[cfg.id] or 0
        local isSelected = (i == selectedEnchantIdx)
        local owned = lv > 0

        local bgColor, bdColor, bdWidth
        if isSelected and owned then
            bgColor = { cfg.color[1], cfg.color[2], cfg.color[3], 60 }
            bdColor = { cfg.color[1], cfg.color[2], cfg.color[3], 220 }
            bdWidth = 2
        elseif isSelected and not owned then
            bgColor = { 50, 55, 75, 200 }
            bdColor = { 140, 150, 180, 180 }
            bdWidth = 2
        elseif owned then
            bgColor = { cfg.color[1], cfg.color[2], cfg.color[3], 30 }
            bdColor = { cfg.color[1], cfg.color[2], cfg.color[3], 100 }
            bdWidth = 1
        else
            bgColor = { 40, 45, 60, 150 }
            bdColor = { 50, 55, 70, 100 }
            bdWidth = 1
        end

        local idx = i  -- 闭包捕获
        table.insert(iconChildren, UI.Panel {
            flexDirection = "column",
            alignItems = "center",
            padding = { 5, 4, 5, 4 },
            borderRadius = 8,
            backgroundColor = bgColor,
            borderColor = bdColor,
            borderWidth = bdWidth,
            gap = 1,
            pointerEvents = "auto",
            onClick = function(self)
                cb.PlayClickSfx()
                selectedEnchantIdx = idx
                local IdleUI = require("IdleUI")
                IdleUI.RefreshCurrentTab()
            end,
            children = {
                UI.Panel {
                    width = 22, height = 22,
                    backgroundImage = cfg.iconImage,
                    backgroundFit = "contain",
                },
                UI.Label {
                    text = owned and ("Lv." .. lv) or "-",
                    fontSize = 10,
                    fontColor = owned
                        and { cfg.color[1], cfg.color[2], cfg.color[3], 255 }
                        or { 80, 90, 110, 150 },
                },
            },
        })
    end

    -- 广告附魔按钮
    if cb.ADS_ENABLED then
        table.insert(iconChildren, UI.Panel {
            flexDirection = "column",
            alignItems = "center",
            justifyContent = "center",
            padding = { 5, 6, 5, 6 },
            borderRadius = 8,
            backgroundColor = { 220, 140, 30, 240 },
            gap = 1,
            pointerEvents = "auto",
            onClick = function(self)
                cb.PlayClickSfx()
                Enchantment.AdEnchant()
            end,
            children = {
                UI.Label {
                    text = "▶",
                    fontSize = 16,
                    fontColor = { 255, 255, 255, 240 },
                },
                UI.Label {
                    text = "附魔",
                    fontSize = 10,
                    fontColor = { 255, 255, 255, 240 },
                },
            },
        })
    end

    -- 效果描述行（显示选中附魔的详情）
    local selCfg = pool[selectedEnchantIdx]
    local selLv = enchants[selCfg.id] or 0
    local descText, descColor
    if selLv > 0 then
        descText = selCfg.name .. " · " .. selCfg.descFunc(selLv)
        descColor = { selCfg.color[1], selCfg.color[2], selCfg.color[3], 220 }
    else
        descText = selCfg.name .. " · 未拥有"
        descColor = { 100, 110, 130, 160 }
    end

    return UI.Panel {
        width = "100%",
        paddingTop = 4,
        borderTopWidth = 1,
        borderColor = { 80, 90, 120, 60 },
        gap = 4,
        children = {
            -- 图标行
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                flexWrap = "wrap",
                children = iconChildren,
            },
            -- 效果描述行
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Panel {
                        width = 16, height = 16,
                        backgroundImage = selCfg.iconImage,
                        backgroundFit = "contain",
                    },
                    UI.Label {
                        text = descText,
                        fontSize = 12,
                        fontColor = descColor,
                    },
                },
            },
        },
    }
end

--- 创建属性行（通用: 价值+倍率 + 专属升级摘要）
function P._CreateStatsRow(IdleMode, totalValue, mult, bt)
    local statChildren = {
        P._StatLabel("价值", tostring(totalValue), { 255, 220, 80, 255 }),
        P._StatLabel("倍率", string.format("x%.2f", mult), { 100, 220, 180, 255 }),
    }
    -- 专属升级摘要（跳过前两个通用升级 auto_drop/base_value）
    local upgrades = IdleMode.GetCurrentBallUpgrades()
    for i = 3, math.min(#upgrades, 5) do
        local cfg = upgrades[i]
        local lv = IdleMode.GetBallAbilityLevel(cfg.id)
        if lv > 0 then
            local valStr = cfg.formatValue(lv, cfg)
            statChildren[#statChildren + 1] = P._StatLabel(
                cfg.name,
                valStr,
                { bt.color[1], bt.color[2], bt.color[3], 255 }
            )
        end
    end
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        flexWrap = "wrap",
        gap = 4,
        children = statChildren,
    }
end

--- 创建属性标签
function P._StatLabel(label, value, color)
    return UI.Panel {
        alignItems = "center", gap = 1,
        children = {
            UI.Label {
                text = label,
                fontSize = 11,
                fontColor = { 140, 150, 170, 180 },
                textAlign = "center",
            },
            UI.Label {
                text = value,
                fontSize = 14,
                fontColor = color,
                textAlign = "center",
            },
        },
    }
end

--- 创建单个能力升级项
---@param cb table 回调表
---@param index number 能力索引
---@param ballUpgrades table 当前球类型的升级列表
---@return table UI 面板
function P.CreateAbilityItem(cb, index, ballUpgrades)
    local abCfg = ballUpgrades[index]
    if not abCfg then return UI.Panel {} end

    local IdleMode = require("IdleMode")
    local level = IdleMode.GetBallAbilityLevel(abCfg.id)
    local isUnlocked = IdleMode.IsBallAbilityUnlocked(index)
    local isMaxed = level >= abCfg.maxLevel

    -- 当前球皮肤图片（用于费用图标）
    local typeIdx = IdleMode.GetCurrentBallType()
    local bt = Config.BALL_TYPES[typeIdx]
    local ballSkinImg = bt and Config.GetBallSkinImage(bt.skinKey) or ""

    -- ====== 锁定状态 ======
    if not isUnlocked then
        -- 查找前一项名称和需要的等级
        local prevCfg = ballUpgrades[index - 1]
        local prevName = prevCfg and prevCfg.name or "前一项"
        local reqLv = abCfg.unlockReq or 0
        local prevLevel = prevCfg and IdleMode.GetBallAbilityLevel(prevCfg.id) or 0

        return UI.Panel {
            id = "idleBallAbility_" .. abCfg.id,
            width = "100%",
            flexDirection = "row",
            padding = { 8, 12, 8, 12 },
            backgroundImage = IMG.CARD,
            backgroundFit = "sliced",
            backgroundSlice = CARD_SLICE,
            imageTint = { 120, 120, 120, 200 },
            borderRadius = 10,
            alignItems = "center", gap = 8,
            opacity = 0.6,
            children = {
                -- 左侧：锁定提示
                UI.Panel {
                    flexGrow = 1, gap = 2,
                    children = {
                        UI.Label {
                            text = "🔒 " .. abCfg.name,
                            fontSize = 16,
                            fontColor = { 90, 95, 120, 180 },
                        },
                        UI.Label {
                            text = abCfg.desc,
                            fontSize = 12,
                            fontColor = { 70, 75, 95, 120 },
                        },
                        UI.Label {
                            text = string.format("需要「%s」达到 Lv.%d (%d/%d)",
                                prevName, reqLv, prevLevel, reqLv),
                            fontSize = 12,
                            fontColor = { 160, 120, 80, 200 },
                        },
                    },
                },
                -- 右侧：锁定标识
                UI.Panel {
                    padding = { 8, 6, 8, 6 },
                    borderRadius = 8,
                    backgroundColor = { 35, 38, 50, 150 },
                    children = {
                        UI.Label {
                            text = "锁定",
                            fontSize = 13,
                            fontColor = { 80, 85, 110, 150 },
                            textAlign = "center",
                        },
                    },
                },
            },
        }
    end

    -- ====== 已解锁状态 ======
    local cost = isMaxed and 0 or Config.GetUpgradeCost(abCfg, level)
    local canAfford = not isMaxed and gameState.idleBallCoins >= cost

    -- 当前值
    local currentValue = abCfg.formatValue(level, abCfg)
    -- 下一级值（预览）
    local nextValue = ""
    if not isMaxed then
        nextValue = abCfg.formatValue(level + 1, abCfg)
    end

    -- 费用文本
    local costText
    if isMaxed then
        costText = "已满级"
    else
        costText = State.FormatNumber(cost)
    end

    -- 卡片背景图
    local cardImg = canAfford and IMG.CARD_HL or IMG.CARD
    local cardTint = canAfford
        and { 80, 200, 120, 200 }
        or nil

    -- 唯一 id
    local cardId = "ballAbCard_" .. abCfg.id
    local btnId  = "ballAbBtn_" .. abCfg.id
    local costId = "ballAbCost_" .. abCfg.id

    local card = UI.Panel {
        id = cardId,
        width = "100%",
        flexDirection = "row",
        padding = { 8, 12, 8, 12 },
        backgroundImage = cardImg,
        backgroundFit = "sliced",
        backgroundSlice = CARD_SLICE,
        imageTint = cardTint,
        borderRadius = 10,
        alignItems = "center", gap = 8,
        pointerEvents = "auto",
        onClick = function()
            if not isMaxed then
                cb.PlayClickSfx()
                cb.PurchaseBallAbility(abCfg.id)
            end
        end,
        children = {
            -- 左侧：名称 + 描述(含属性值) — flex 结构与升级面板一致
            UI.Panel {
                flexGrow = 1, flexShrink = 1, gap = 1, pointerEvents = "none",
                children = {
                    -- 第一行：名称 + 等级标签（flex-row）
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label {
                                text = abCfg.name,
                                fontSize = 14,
                                fontColor = { 230, 240, 255, 255 },
                            },
                            UI.Panel {
                                padding = { 4, 1, 4, 1 },
                                borderRadius = 3,
                                backgroundColor = isMaxed
                                    and { 255, 200, 50, 40 }
                                    or { 80, 200, 120, 30 },
                                children = {
                                    UI.Label {
                                        text = isMaxed and "MAX" or ("Lv." .. level),
                                        fontSize = 10,
                                        fontColor = isMaxed
                                            and { 255, 220, 80, 255 }
                                            or { 80, 200, 120, 220 },
                                    },
                                },
                            },
                        },
                    },
                    -- 第二行：描述 + 当前效果值
                    UI.Label {
                        text = isMaxed
                            and (abCfg.desc .. "  " .. currentValue)
                            or (abCfg.desc .. "  " .. currentValue .. " → " .. nextValue),
                        fontSize = 11,
                        fontColor = { 160, 170, 190, 200 },
                    },
                },
            },
            -- 右侧：费用按钮（与升级面板一致）
            UI.Panel {
                id = btnId,
                minWidth = 52,
                padding = { 8, 5, 8, 5 },
                borderRadius = 6,
                flexShrink = 0,
                backgroundColor = isMaxed
                    and { 50, 50, 40, 180 }
                    or (canAfford and { 50, 140, 70, 220 } or { 40, 45, 60, 200 }),
                borderColor = isMaxed
                    and { 80, 80, 60, 100 }
                    or (canAfford and { 80, 200, 100, 150 } or { 55, 60, 80, 100 }),
                borderWidth = 1,
                justifyContent = "center", alignItems = "center",
                pointerEvents = "none",
                children = {
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
                                    backgroundImage = ballSkinImg,
                                },
                                UI.Label {
                                    id = costId,
                                    text = costText,
                                    fontSize = 12,
                                    fontColor = canAfford
                                        and { 180, 255, 180, 255 }
                                        or { 110, 120, 150, 180 },
                                },
                            },
                    },
                },
            },
        },
    }

    -- 记录引用供轻量更新
    if not isMaxed then
        abilityRefs[abCfg.id] = { canAfford = canAfford }
    end

    return card
end

--- 轻量更新 header 中的球币数字（不重建）
---@param root table UI 根节点
function P.UpdateHeader(root)
    if not root then return end
    local lbl = root:FindById("ballCoinLabel")
    if lbl then
        lbl:SetStyle({ text = State.FormatNumber(gameState.idleBallCoins) })
    end
end

--- 轻量更新所有能力项的 canAfford 样式（不重建）
--- 返回 true 表示有变化
---@param root table UI 根节点
---@return boolean changed
function P.UpdateAfford(root)
    if not root then return false end
    local IdleMode = require("IdleMode")
    local ballUpgrades = IdleMode.GetCurrentBallUpgrades()
    local changed = false

    for _, abCfg in ipairs(ballUpgrades) do
        local ref = abilityRefs[abCfg.id]
        if ref then  -- 非满级项才有 ref
            local lv = IdleMode.GetBallAbilityLevel(abCfg.id)
            local cost = Config.GetUpgradeCost(abCfg, lv)
            local canAfford = (lv < abCfg.maxLevel) and (gameState.idleBallCoins >= cost)

            if canAfford ~= ref.canAfford then
                ref.canAfford = canAfford
                changed = true
                -- 更新卡片背景
                local card = root:FindById("ballAbCard_" .. abCfg.id)
                if card then
                    card:SetStyle({
                        backgroundImage = canAfford and IMG.CARD_HL or IMG.CARD,
                        imageTint = canAfford and { 80, 200, 120, 200 } or nil,
                    })
                end
                -- 更新按钮颜色+边框
                local btn = root:FindById("ballAbBtn_" .. abCfg.id)
                if btn then
                    btn:SetStyle({
                        backgroundColor = canAfford
                            and { 50, 140, 70, 220 }
                            or { 40, 45, 60, 200 },
                        borderColor = canAfford
                            and { 80, 200, 100, 150 }
                            or { 55, 60, 80, 100 },
                    })
                end
                -- 更新费用文本颜色
                local costLbl = root:FindById("ballAbCost_" .. abCfg.id)
                if costLbl then
                    costLbl:SetStyle({
                        fontColor = canAfford
                            and { 180, 255, 180, 255 }
                            or { 110, 120, 150, 180 },
                    })
                end
            end
        end
    end
    return changed
end

return P
