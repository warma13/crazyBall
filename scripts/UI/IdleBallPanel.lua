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

-- 当前选中查看的附魔索引（1-based，对应 Config.ENCHANTMENTS）
local selectedEnchantIdx = 1

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

--- 创建弹珠面板（当前弹珠信息 + 能力升级列表）
---@param cb table 回调表
---@return table UI 面板
function P.CreateBallList(cb)
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
        backgroundColor = { bt.color[1], bt.color[2], bt.color[3], 40 },
        borderColor = { bt.color[1], bt.color[2], bt.color[3], 120 },
        borderWidth = 2,
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
                UI.Label {
                    text = cfg.icon,
                    fontSize = 16,
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
                    UI.Label {
                        text = selCfg.icon,
                        fontSize = 13,
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
    local goalLevel = abCfg.goalLevel or 1
    local goalDone = level >= goalLevel

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
            padding = { 8, 8, 8, 8 },
            backgroundColor = { 22, 24, 38, 180 },
            borderColor = { 40, 42, 58, 120 },
            borderWidth = 1,
            borderRadius = 10,
            alignItems = "center", gap = 8,
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

    -- 目标进度文本
    local goalText
    if goalDone then
        goalText = "✓ 目标达成"
    else
        goalText = string.format("目标: Lv.%d/%d", level, goalLevel)
    end

    -- 颜色
    local bgColor, borderColor
    if goalDone and isMaxed then
        bgColor = { 35, 40, 30, 200 }
        borderColor = { 100, 100, 60, 120 }
    elseif canAfford then
        bgColor = { 30, 45, 60, 220 }
        borderColor = { 80, 180, 120, 200 }
    else
        bgColor = { 28, 32, 50, 200 }
        borderColor = { 45, 55, 75, 150 }
    end

    return UI.Panel {
        id = "idleBallAbility_" .. abCfg.id,
        width = "100%",
        flexDirection = "row",
        padding = { 8, 8, 8, 8 },
        backgroundColor = bgColor,
        borderColor = borderColor,
        borderWidth = canAfford and 2 or 1.5,
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
            -- 左侧：名称 + 描述 + 当前值 + 目标进度
            UI.Panel {
                flexGrow = 1, gap = 2, pointerEvents = "none",
                children = {
                    -- 名称 + 等级
                    UI.Label {
                        text = abCfg.name .. (isMaxed and " MAX" or ("  Lv." .. level)),
                        fontSize = 16,
                        fontColor = isMaxed
                            and { 255, 220, 80, 255 }
                            or { 220, 230, 250, 255 },
                    },
                    -- 描述
                    UI.Label {
                        text = abCfg.desc,
                        fontSize = 12,
                        fontColor = { 120, 140, 170, 180 },
                    },
                    -- 当前值 → 下一级值
                    UI.Label {
                        text = isMaxed
                            and currentValue
                            or (currentValue .. " → " .. nextValue),
                        fontSize = 13,
                        fontColor = isMaxed
                            and { 180, 200, 140, 200 }
                            or { 100, 200, 160, 220 },
                    },
                    -- 目标进度
                    UI.Label {
                        text = goalText,
                        fontSize = 11,
                        fontColor = goalDone
                            and { 120, 220, 100, 220 }
                            or { 200, 170, 80, 200 },
                    },
                },
            },
            -- 右侧：费用按钮
            UI.Panel {
                padding = { 8, 6, 8, 6 },
                borderRadius = 8,
                backgroundColor = isMaxed
                    and { 60, 60, 40, 150 }
                    or (canAfford and { 50, 140, 70, 220 } or { 40, 45, 60, 200 }),
                pointerEvents = "none",
                flexDirection = "row", alignItems = "center", gap = 4,
                children = isMaxed
                    and {
                        UI.Label {
                            text = "已满级",
                            fontSize = 13,
                            fontColor = { 180, 180, 120, 180 },
                            textAlign = "center",
                        },
                    }
                    or {
                        UI.Panel {
                            width = 16, height = 16, borderRadius = 8,
                            backgroundImage = ballSkinImg,
                        },
                        UI.Label {
                            text = costText,
                            fontSize = 13,
                            fontColor = canAfford
                                and { 180, 255, 180, 255 }
                                or { 110, 120, 150, 180 },
                        },
                    },
            },
        },
    }
end

return P
