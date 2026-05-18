-- ============================================================================
-- UI/IdleSkillPanel.lua - 放置模式技能面板
-- 技能项采用边框进度条风格（类似 DropButton）：
--   CD 中灰色 + 边框顺时针填充，满后自动释放（高亮闪烁）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local State = require("State")

local gameState = State.gameState

local P = {}

-- UI 背景图路径
local IMG = {
    CARD       = "image/ui_card_normal_20260517160219.png",
    CARD_HL    = "image/ui_card_highlight_20260517160012.png",
    POPUP      = "image/ui_popup_bg_20260517160108.png",
}
local CARD_SLICE = { top = 20, right = 20, bottom = 20, left = 20 }
local POPUP_SLICE = { top = 30, right = 30, bottom = 30, left = 30 }

-- 技能项 UI 引用表，用于每帧实时更新（不重建 UI 树）
-- { [skillId] = { borderTop, borderRight, borderBottom, borderLeft, innerPanel, nameLbl, statusLbl, iconLbl } }
local skillItemRefs_ = {}

-- ============================================================================
-- 配色
-- ============================================================================
local COLORS = {
    -- 边框（就绪时亮色）
    borderReady   = { 160, 90, 230, 255 },
    borderDim     = { 35, 25, 50, 255 },
    -- buff 激活边框
    borderBuff    = { 60, 220, 120, 255 },
    borderBuffDim = { 20, 50, 30, 255 },

    -- 背景
    bgReady       = { 50, 30, 90, 255 },
    bgCooldown    = { 30, 30, 40, 220 },
    bgBuff        = { 25, 70, 45, 255 },

    -- 高光 / 阴影
    innerHighlight = { 180, 130, 255, 80 },
    innerShadow    = { 20, 8, 40, 120 },
    buffHighlight  = { 100, 255, 180, 80 },

    -- 文字
    textReady     = { 230, 235, 250, 255 },
    textCooldown  = { 100, 100, 120, 180 },
    textBuff      = { 180, 255, 200, 255 },
    textShadow    = { 15, 5, 30, 140 },
    statusReady   = { 180, 140, 255, 200 },
    statusCD      = { 200, 180, 60, 200 },
    statusBuff    = { 80, 255, 160, 230 },
}

local ITEM_HEIGHT = 58
local BORDER_W    = 2.5

-- ============================================================================
-- 关卡选择弹窗
-- ============================================================================

local LEVEL_SELECT_ID = "levelSelectOverlay"

--- 关闭关卡选择弹窗
local function HideLevelSelect()
    local IdleUI = require("IdleUI")
    local root = IdleUI.GetRoot()
    if not root then return end
    local old = root:FindById(LEVEL_SELECT_ID)
    if old then root:RemoveChild(old) end
end

--- 打开关卡选择弹窗
local function ShowLevelSelect()
    local IdleUI = require("IdleUI")
    local root = IdleUI.GetRoot()
    if not root then return end
    HideLevelSelect()

    local IdleMode = require("IdleMode")
    local currentLevel = gameState.idleLevel
    local maxUnlocked  = gameState.idleMaxUnlockedLevel or 1

    -- 构建关卡网格项（显示全部关卡，未解锁灰色）
    local totalLevels = #Config.BALL_TYPES
    local cells = {}
    for lv = 1, totalLevels do
        local isCurrent = (lv == currentLevel)
        local isUnlocked = (lv <= maxUnlocked)

        local bgColor, bdColor, bdWidth, txtColor
        if isCurrent then
            bgColor  = { 80, 140, 255, 220 }
            bdColor  = { 140, 200, 255, 255 }
            bdWidth  = 2
            txtColor = { 255, 255, 255, 255 }
        elseif isUnlocked then
            bgColor  = { 45, 50, 70, 220 }
            bdColor  = { 70, 80, 110, 120 }
            bdWidth  = 1
            txtColor = { 180, 190, 210, 230 }
        else
            bgColor  = { 30, 32, 42, 180 }
            bdColor  = { 50, 55, 70, 80 }
            bdWidth  = 1
            txtColor = { 70, 75, 90, 150 }
        end

        table.insert(cells, UI.Panel {
            width = 48, height = 48,
            borderRadius = 10,
            backgroundColor = bgColor,
            borderColor = bdColor,
            borderWidth = bdWidth,
            justifyContent = "center",
            alignItems = "center",
            pointerEvents = isUnlocked and "auto" or "none",
            onClick = isUnlocked and function()
                if lv ~= currentLevel then
                    IdleMode.SwitchToLevel(lv)
                    State.uiDirty = true
                    local IdleUI2 = require("IdleUI")
                    IdleUI2.RefreshCurrentTab()
                end
                HideLevelSelect()
            end or nil,
            children = {
                UI.Label {
                    text = isUnlocked and tostring(lv) or "🔒",
                    fontSize = isUnlocked and 16 or 14,
                    fontColor = txtColor,
                    textAlign = "center",
                },
            },
        })
    end

    local overlay = UI.Panel {
        id = LEVEL_SELECT_ID,
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        onClick = function() HideLevelSelect() end,
        children = {
            UI.Panel {
                width = "85%",
                maxWidth = 320,
                backgroundImage = IMG.POPUP,
                backgroundFit = "sliced",
                backgroundSlice = POPUP_SLICE,
                padding = { 16, 16, 16, 16 },
                gap = 12,
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function() end, -- 阻止点击穿透
                children = {
                    -- 标题
                    UI.Label {
                        text = "选择关卡",
                        fontSize = 18,
                        fontColor = { 120, 200, 255, 255 },
                        textAlign = "center",
                    },
                    -- 关卡网格
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        flexWrap = "wrap",
                        justifyContent = "center",
                        gap = 8,
                        children = cells,
                    },
                    -- 关闭按钮
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        marginTop = 4,
                        children = {
                            UI.Panel {
                                paddingLeft = 20, paddingRight = 20,
                                paddingTop = 6, paddingBottom = 6,
                                borderRadius = 8,
                                backgroundColor = { 60, 65, 85, 200 },
                                borderColor = { 100, 110, 140, 120 },
                                borderWidth = 1,
                                pointerEvents = "auto",
                                onClick = function() HideLevelSelect() end,
                                children = {
                                    UI.Label {
                                        text = "关闭",
                                        fontSize = 13,
                                        fontColor = { 180, 190, 220, 220 },
                                        textAlign = "center",
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }

    root:AddChild(overlay)
end

-- ============================================================================
-- Header
-- ============================================================================

function P.CreateSkillHeader()
    local IdleMode = require("IdleMode")
    local allDone, done, total = IdleMode.CheckAllGoalsDone()
    local currentLevel = gameState.idleLevel
    local maxUnlocked = gameState.idleMaxUnlockedLevel

    local progressText
    if currentLevel == maxUnlocked then
        progressText = string.format("进度 %d/%d", done, total)
    else
        progressText = "已达标"
    end

    local progress = (total > 0) and (done / total) or 0
    if currentLevel ~= maxUnlocked then progress = 1 end

    return UI.Panel {
        id = "idleSkillHeader",
        width = "100%",
        backgroundColor = { 0, 0, 0, 0 },
        borderColor = { 120, 180, 255, 60 },
        borderWidth = { 0, 0, 1, 0 },
        children = {
            -- 可点击的关卡按钮
            UI.Panel {
                width = "100%",
                alignItems = "center",
                padding = { 6, 6, 4, 6 },
                children = {
                    UI.Button {
                        text = string.format("阶段 %d / %d  ▼", currentLevel, maxUnlocked),
                        fontSize = 14,
                        variant = "ghost",
                        fontColor = { 120, 200, 255, 255 },
                        onClick = function(self)
                            ShowLevelSelect()
                        end,
                    },
                    UI.Label {
                        text = progressText,
                        fontSize = 10,
                        fontColor = allDone and { 100, 255, 150, 200 } or { 140, 150, 180, 180 },
                        textAlign = "center",
                    },
                },
            },
            -- 进度条
            UI.Panel {
                width = "100%",
                height = 4,
                backgroundColor = { 30, 35, 55, 200 },
                children = {
                    UI.Panel {
                        width = string.format("%.1f%%", progress * 100),
                        height = "100%",
                        backgroundColor = allDone and { 100, 255, 150, 220 } or { 80, 160, 255, 200 },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 技能列表
-- ============================================================================

function P.CreateSkillList()
    skillItemRefs_ = {}  -- 重建时清空引用
    local items = {}
    local hasSkills = false

    for _, cfg in ipairs(Config.IDLE.SKILLS) do
        local lv = gameState.idleSkills[cfg.id] or 0
        if lv > 0 then
            hasSkills = true
            table.insert(items, P.CreateSkillItem(cfg, lv))
        end
    end

    if not hasSkills then
        table.insert(items, UI.Panel {
            width = "100%",
            padding = { 20, 12, 20, 12 },
            alignItems = "center",
            children = {
                UI.Label {
                    text = "完成所有弹珠升级目标后",
                    fontSize = 13,
                    fontColor = { 140, 150, 180, 160 },
                    textAlign = "center",
                },
                UI.Label {
                    text = "即可获得三选一技能",
                    fontSize = 13,
                    fontColor = { 140, 150, 180, 160 },
                    textAlign = "center",
                },
            },
        })
    end

    return UI.Panel {
        id = "idleSkillList",
        width = "100%",
        gap = 6,
        children = items,
    }
end

-- ============================================================================
-- 单个技能项（DropButton 风格：边框进度条 + 高光阴影）
-- ============================================================================

function P.CreateSkillItem(cfg, level)
    local ic = cfg.iconColor or { 180, 180, 180 }
    local isMaxed = level >= cfg.maxLevel
    local icon = cfg.icon or string.sub(cfg.name, 1, 3)
    local effectText = cfg.formatValue(level, cfg)
    local levelTag = isMaxed and "MAX" or ("Lv." .. level)

    local IdleMode = require("IdleMode")
    local cd = IdleMode.GetSkillCooldown(cfg.id)
    local typeLabel = "瞬发"
    local cdLabel = string.format("CD %.0fs", cd)

    local itemW = "100%"

    -- 四段边框（绝对定位，顺时针填充）
    local borderTop = UI.Panel {
        position = "absolute", top = 0, left = 0,
        width = "100%", height = BORDER_W,
        backgroundColor = COLORS.borderReady,
        borderRadius = { BORDER_W, BORDER_W, 0, 0 },
        pointerEvents = "none",
    }
    local borderRight = UI.Panel {
        position = "absolute", top = 0, right = 0,
        width = BORDER_W, height = "100%",
        backgroundColor = COLORS.borderReady,
        borderRadius = { 0, BORDER_W, BORDER_W, 0 },
        pointerEvents = "none",
    }
    local borderBottom = UI.Panel {
        position = "absolute", bottom = 0, right = 0,
        width = "100%", height = BORDER_W,
        backgroundColor = COLORS.borderReady,
        borderRadius = { 0, 0, BORDER_W, BORDER_W },
        pointerEvents = "none",
    }
    local borderLeft = UI.Panel {
        position = "absolute", bottom = 0, left = 0,
        width = BORDER_W, height = "100%",
        backgroundColor = COLORS.borderReady,
        borderRadius = { BORDER_W, 0, 0, BORDER_W },
        pointerEvents = "none",
    }

    -- 顶部高光
    local highlightBar = UI.Panel {
        position = "absolute",
        top = BORDER_W, left = BORDER_W + 4, right = BORDER_W + 4,
        height = 2,
        backgroundGradient = {
            type = "linear", direction = "to-bottom",
            from = COLORS.innerHighlight,
            to = { COLORS.innerHighlight[1], COLORS.innerHighlight[2], COLORS.innerHighlight[3], 0 },
        },
        pointerEvents = "none",
    }

    -- 底部阴影
    local shadowBar = UI.Panel {
        position = "absolute",
        bottom = BORDER_W, left = BORDER_W + 4, right = BORDER_W + 4,
        height = 3,
        backgroundGradient = {
            type = "linear", direction = "to-top",
            from = COLORS.innerShadow,
            to = { COLORS.innerShadow[1], COLORS.innerShadow[2], COLORS.innerShadow[3], 0 },
        },
        pointerEvents = "none",
    }

    -- 图标
    local iconLbl = UI.Label {
        text = icon,
        fontSize = 18,
        fontColor = { ic[1], ic[2], ic[3], 255 },
        textAlign = "center",
        pointerEvents = "none",
    }

    -- 名称行
    local nameLbl = UI.Label {
        text = cfg.name .. "  " .. levelTag,
        fontSize = 13,
        fontColor = COLORS.textReady,
        textShadow = { x = 0, y = 1, blur = 0, color = COLORS.textShadow },
        pointerEvents = "none",
    }

    -- 效果行
    local effectLbl = UI.Label {
        text = effectText .. "   " .. typeLabel .. " | " .. cdLabel,
        fontSize = 9,
        fontColor = { 160, 170, 200, 180 },
        pointerEvents = "none",
    }

    -- 状态行（就绪/CD/buff）
    local statusLbl = UI.Label {
        text = "就绪",
        fontSize = 11,
        fontColor = COLORS.statusReady,
        textAlign = "right",
        pointerEvents = "none",
    }

    -- 内容面板（边框内区域）
    local innerPanel = UI.Panel {
        position = "absolute",
        top = BORDER_W, left = BORDER_W, right = BORDER_W, bottom = BORDER_W,
        flexDirection = "row",
        alignItems = "center",
        padding = { 8, 6, 8, 6 },
        gap = 8,
        backgroundColor = COLORS.bgReady,
        borderRadius = 6,
        overflow = "hidden",
        pointerEvents = "none",
        children = {
            -- 图标区
            UI.Panel {
                width = 34, height = 34,
                justifyContent = "center", alignItems = "center",
                borderRadius = 7,
                backgroundColor = { ic[1], ic[2], ic[3], 40 },
                borderColor = { ic[1], ic[2], ic[3], 60 },
                borderWidth = 1,
                children = { iconLbl },
            },
            -- 文字区
            UI.Panel {
                flexGrow = 1, flexShrink = 1, gap = 2,
                children = {
                    nameLbl,
                    effectLbl,
                },
            },
            -- 状态区
            UI.Panel {
                width = 50,
                alignItems = "flex-end",
                justifyContent = "center",
                children = { statusLbl },
            },
        },
    }

    -- 外层容器（暗底 = 未填充边框背景色）
    local outer = UI.Panel {
        width = itemW,
        height = ITEM_HEIGHT,
        backgroundColor = COLORS.borderDim,
        borderRadius = 8,
        overflow = "hidden",
        children = {
            borderTop, borderRight, borderBottom, borderLeft,
            innerPanel,
            highlightBar, shadowBar,
        },
    }

    -- 保存引用供实时更新
    skillItemRefs_[cfg.id] = {
        outer       = outer,
        innerPanel  = innerPanel,
        borderTop   = borderTop,
        borderRight = borderRight,
        borderBottom = borderBottom,
        borderLeft  = borderLeft,
        highlightBar = highlightBar,
        nameLbl     = nameLbl,
        statusLbl   = statusLbl,
        iconLbl     = iconLbl,
        ic          = ic,
        cfg         = cfg,
    }

    return outer
end

-- ============================================================================
-- 实时更新（每帧，不重建 UI）
-- ============================================================================

--- 更新边框四段填充（顺时针进度 0~1）
---@param refs table 技能项引用
---@param progress number 0~1
---@param borderColor table RGBA
local function UpdateBorder(refs, progress, borderColor)
    progress = math.max(0, math.min(1, progress))
    -- 简化：用百分比宽高模拟（实际周长分四段）
    -- 上(0~0.25)→右(0.25~0.5)→下(0.5~0.75)→左(0.75~1)
    local frac = 0.25

    -- 上边框
    local topProg = math.min(progress / frac, 1)
    refs.borderTop:SetStyle({
        width = string.format("%.1f%%", topProg * 100),
        backgroundColor = borderColor,
    })

    -- 右边框
    local rightProg = math.max(0, math.min((progress - frac) / frac, 1))
    refs.borderRight:SetStyle({
        height = string.format("%.1f%%", rightProg * 100),
        backgroundColor = borderColor,
    })

    -- 下边框
    local bottomProg = math.max(0, math.min((progress - frac * 2) / frac, 1))
    refs.borderBottom:SetStyle({
        width = string.format("%.1f%%", bottomProg * 100),
        backgroundColor = borderColor,
    })

    -- 左边框
    local leftProg = math.max(0, math.min((progress - frac * 3) / frac, 1))
    refs.borderLeft:SetStyle({
        height = string.format("%.1f%%", leftProg * 100),
        backgroundColor = borderColor,
    })
end

--- 每帧更新所有技能项的 CD/Buff 视觉
function P.UpdateSkillItems()
    local IdleMode = require("IdleMode")
    local states = IdleMode.GetSkillStates()

    for _, st in ipairs(states) do
        local refs = skillItemRefs_[st.id]
        if refs then
            local ic = refs.ic

            if st.cdRemaining > 0 then
                -- CD 中：灰色，边框进度条
                local cdTotal = IdleMode.GetSkillCooldown(st.id)
                local cdProg = (cdTotal > 0) and (1 - st.cdRemaining / cdTotal) or 0

                refs.innerPanel:SetStyle({ backgroundColor = COLORS.bgCooldown })
                refs.nameLbl:SetStyle({ fontColor = COLORS.textCooldown })
                refs.statusLbl:SetStyle({
                    text = string.format("%.0fs", math.ceil(st.cdRemaining)),
                    fontColor = COLORS.statusCD,
                })
                refs.highlightBar:SetStyle({
                    backgroundGradient = {
                        type = "linear", direction = "to-bottom",
                        from = { 80, 70, 100, 40 },
                        to = { 80, 70, 100, 0 },
                    },
                })
                refs.outer:SetStyle({ backgroundColor = COLORS.borderDim })
                UpdateBorder(refs, cdProg, { ic[1], ic[2], ic[3], 180 })

            else
                -- 就绪（自动释放，短暂闪烁后又进入 CD）
                refs.innerPanel:SetStyle({ backgroundColor = COLORS.bgReady })
                refs.nameLbl:SetStyle({ fontColor = COLORS.textReady })
                refs.statusLbl:SetStyle({
                    text = "就绪",
                    fontColor = COLORS.statusReady,
                })
                refs.highlightBar:SetStyle({
                    backgroundGradient = {
                        type = "linear", direction = "to-bottom",
                        from = COLORS.innerHighlight,
                        to = { COLORS.innerHighlight[1], COLORS.innerHighlight[2], COLORS.innerHighlight[3], 0 },
                    },
                })
                refs.outer:SetStyle({ backgroundColor = COLORS.borderDim })
                UpdateBorder(refs, 1, COLORS.borderReady)
            end
        end
    end
end

-- ============================================================================
-- 三选一弹窗
-- ============================================================================

function P.CreateSkillPickPopup(choices, onPick)
    local cards = {}

    for _, cfg in ipairs(choices) do
        local ic = cfg.iconColor or { 180, 180, 180 }
        local curLv = gameState.idleSkills[cfg.id] or 0
        local nextLv = math.min(curLv + 1, cfg.maxLevel)
        local isNew = curLv == 0

        local effectText = cfg.formatValue(nextLv, cfg)
        local lvLabel = isNew and "新技能!" or string.format("Lv.%d → %d", curLv, nextLv)

        table.insert(cards, UI.Panel {
            width = "100%",
            padding = { 12, 10, 12, 10 },
            backgroundImage = IMG.CARD_HL,
            backgroundFit = "sliced",
            backgroundSlice = CARD_SLICE,
            imageTint = { ic[1], ic[2], ic[3], 200 },
            gap = 4,
            pointerEvents = "auto",
            onClick = function()
                if onPick then onPick(cfg.id) end
            end,
            children = {
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 8,
                    pointerEvents = "none",
                    children = {
                        UI.Panel {
                            width = 40, height = 40,
                            justifyContent = "center", alignItems = "center",
                            borderRadius = 10,
                            backgroundColor = { ic[1], ic[2], ic[3], 60 },
                            borderColor = { ic[1], ic[2], ic[3], 120 },
                            borderWidth = 1,
                            children = {
                                UI.Label {
                                    text = cfg.icon or string.sub(cfg.name, 1, 3),
                                    fontSize = 18,
                                    fontColor = { ic[1], ic[2], ic[3], 255 },
                                    textAlign = "center",
                                },
                            },
                        },
                        UI.Panel {
                            flexGrow = 1, gap = 1,
                            children = {
                                UI.Label {
                                    text = cfg.name,
                                    fontSize = 16,
                                    fontColor = { 255, 255, 255, 255 },
                                },
                                UI.Label {
                                    text = lvLabel,
                                    fontSize = 11,
                                    fontColor = isNew and { 100, 255, 150, 255 } or { ic[1], ic[2], ic[3], 200 },
                                },
                            },
                        },
                    },
                },
                UI.Label {
                    text = cfg.desc,
                    fontSize = 11,
                    fontColor = { 180, 190, 210, 200 },
                    pointerEvents = "none",
                },
                UI.Label {
                    text = effectText,
                    fontSize = 13,
                    fontColor = { ic[1], ic[2], ic[3], 255 },
                    pointerEvents = "none",
                },
            },
        })
    end

    return UI.Panel {
        id = "skillPickOverlay",
        position = "absolute",
        width = "100%", height = "100%",
        left = 0, top = 0,
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center",
        alignItems = "center",
        padding = { 16, 20, 16, 20 },
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = "100%",
                maxWidth = 320,
                gap = 8,
                padding = { 16, 14, 16, 14 },
                backgroundImage = IMG.POPUP,
                backgroundFit = "sliced",
                backgroundSlice = POPUP_SLICE,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "选择一个技能",
                        fontSize = 18,
                        fontColor = { 255, 220, 80, 255 },
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "完成升级目标，获得主动技能",
                        fontSize = 11,
                        fontColor = { 160, 170, 200, 160 },
                        textAlign = "center",
                    },
                    UI.Panel {
                        width = "100%", gap = 6,
                        children = cards,
                    },
                },
            },
        },
    }
end

return P
