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

-- （关卡选择弹窗已移除，改为自动循环）

-- ============================================================================
-- Header
-- ============================================================================

function P.CreateSkillHeader()
    local IdleMode = require("IdleMode")
    local allDone, done, total = IdleMode.CheckAllGoalsDone()
    local totalBalls = #Config.BALL_TYPES
    local cycle = IdleMode.GetCycleCount()
    local stageInCycle = ((gameState.idleLevel - 1) % totalBalls) + 1

    local progressText = string.format("进度 %d/%d", done, total)
    local cycleMult = IdleMode.GetCycleMultiplier()
    local cycleTag = cycle > 0 and string.format("  x%d", cycleMult) or ""

    local btnText = string.format("阶段 %d / %d  %s%s",
        stageInCycle, totalBalls, progressText, cycleTag)

    return UI.Panel {
        id = "idleSkillHeader",
        width = "100%",
        padding = { 6, 6, 6, 6 },
        alignItems = "center",
        children = {
            UI.Panel {
                paddingLeft = 16, paddingRight = 16,
                paddingTop = 6, paddingBottom = 6,
                backgroundImage = IMG.CARD,
                backgroundFit = "sliced",
                backgroundSlice = CARD_SLICE,
                borderRadius = 8,
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = btnText,
                        fontSize = 13,
                        fontColor = { 120, 200, 255, 255 },
                        textAlign = "center",
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
-- 单个技能项（卡片图片背景）
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

    -- 图标（优先使用图片，1:1 铺满行高）
    local iconSize = ITEM_HEIGHT - 8 * 2  -- 减去上下 padding
    local iconLbl
    if cfg.iconImage then
        iconLbl = UI.Panel {
            width = iconSize, height = iconSize,
            backgroundImage = cfg.iconImage,
            backgroundFit = "contain",
            borderRadius = 4,
            pointerEvents = "none",
        }
    else
        iconLbl = UI.Label {
            text = icon,
            fontSize = 18,
            fontColor = { ic[1], ic[2], ic[3], 255 },
            textAlign = "center",
            pointerEvents = "none",
        }
    end

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

    -- 卡片面板
    local outer = UI.Panel {
        width = "100%",
        height = ITEM_HEIGHT,
        flexDirection = "row",
        alignItems = "center",
        paddingTop = 8, paddingRight = 12, paddingBottom = 8, paddingLeft = 12,
        gap = 8,
        backgroundImage = IMG.CARD,
        backgroundFit = "sliced",
        backgroundSlice = CARD_SLICE,
        borderRadius = 8,
        overflow = "hidden",
        children = {
            -- 图标区（1:1 铺满行高）
            UI.Panel {
                width = iconSize, height = iconSize,
                justifyContent = "center", alignItems = "center",
                borderRadius = 7,
                backgroundColor = cfg.iconImage and { 0, 0, 0, 0 } or { ic[1], ic[2], ic[3], 40 },
                borderColor = cfg.iconImage and { 0, 0, 0, 0 } or { ic[1], ic[2], ic[3], 60 },
                borderWidth = cfg.iconImage and 0 or 1,
                overflow = "hidden",
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

    -- 保存引用供实时更新
    skillItemRefs_[cfg.id] = {
        outer       = outer,
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

--- 每帧更新所有技能项的 CD/Buff 视觉
function P.UpdateSkillItems()
    local IdleMode = require("IdleMode")
    local states = IdleMode.GetSkillStates()

    for _, st in ipairs(states) do
        local refs = skillItemRefs_[st.id]
        if refs then
            if st.buffRemaining and st.buffRemaining > 0 then
                -- buff 激活中：绿色高亮
                refs.outer:SetStyle({
                    imageTint = { 40, 120, 70, 220 },
                })
                refs.nameLbl:SetStyle({ fontColor = COLORS.textBuff })
                refs.statusLbl:SetStyle({
                    text = string.format("%.1fs", st.buffRemaining),
                    fontColor = COLORS.buffHighlight,
                })
            elseif st.cdRemaining > 0 then
                -- CD 中：灰色调
                refs.outer:SetStyle({
                    imageTint = { 60, 60, 80, 200 },
                })
                refs.nameLbl:SetStyle({ fontColor = COLORS.textCooldown })
                refs.statusLbl:SetStyle({
                    text = string.format("%.0fs", math.ceil(st.cdRemaining)),
                    fontColor = COLORS.statusCD,
                })
            else
                -- 就绪
                refs.outer:SetStyle({
                    imageTint = nil,
                })
                refs.nameLbl:SetStyle({ fontColor = COLORS.textReady })
                refs.statusLbl:SetStyle({
                    text = "就绪",
                    fontColor = COLORS.statusReady,
                })
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
                            backgroundColor = cfg.iconImage and { 0, 0, 0, 0 } or { ic[1], ic[2], ic[3], 60 },
                            borderColor = cfg.iconImage and { 0, 0, 0, 0 } or { ic[1], ic[2], ic[3], 120 },
                            borderWidth = cfg.iconImage and 0 or 1,
                            backgroundImage = cfg.iconImage or nil,
                            backgroundFit = cfg.iconImage and "contain" or nil,
                            children = cfg.iconImage and {} or {
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
