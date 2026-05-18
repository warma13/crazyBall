-- ============================================================================
-- UI/DropButton.lua - 掉落按钮样式组件
-- 像素风紫色按钮：上高光、下阴影
-- 冷却时按钮变灰，边框沿四周顺时针填充显示冷却进度
-- ============================================================================

local UI = require("urhox-libs/UI")

local M = {}

-- ============================================================================
-- 配色
-- ============================================================================
local COLORS = {
    -- 边框（冷却完成时的亮色）
    borderReady   = { 160, 90, 230, 255 },   -- 亮紫
    -- 边框底色（冷却中未填充部分）
    borderDim     = { 35, 25, 50, 255 },     -- 暗底

    -- 按钮底色
    bgReady       = { 80, 35, 140, 255 },    -- 就绪紫
    bgHover       = { 110, 55, 180, 255 },   -- hover 亮紫
    bgPressed     = { 55, 20, 100, 255 },    -- 按下暗紫
    bgCooldown    = { 40, 38, 48, 255 },     -- 冷却灰

    -- 内层高光/阴影
    innerHighlight = { 180, 130, 255, 100 },
    innerShadow    = { 20, 8, 40, 160 },

    -- 文字
    textReady     = { 255, 255, 255, 255 },
    textShadow    = { 30, 8, 60, 180 },
    textCooldown  = { 90, 85, 100, 200 },
}

--- 创建掉落按钮
---@param opts table { text, onClick, width, height, fontSize, borderWidth }
---@return Widget
function M.Create(opts)
    opts = opts or {}
    local text      = opts.text or "掉落"
    local onClick   = opts.onClick
    local btnWidth  = opts.width or 220
    local btnHeight = opts.height or 56
    local fontSize  = opts.fontSize or 22
    local borderW   = opts.borderWidth or 3

    -- 状态
    local isPressed  = false
    local isCooling  = false   -- 当前是否冷却中
    local lastProgress = 1     -- 上次进度

    -- ── 内部控件引用 ──
    local btnLabel, innerPanel, outerPanel
    local borderTop, borderRight, borderBottom, borderLeft

    -- 边框段的尺寸计算
    -- 内区域尺寸（边框围绕的区域）
    local innerW = btnWidth
    local innerH = btnHeight

    -- 四段边框面板（顺时针：上→右→下→左）
    -- 上边框：从左到右填充
    borderTop = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = 0,   -- 动态更新
        height = borderW,
        backgroundColor = COLORS.borderReady,
        pointerEvents = "none",
    }

    -- 右边框：从上到下填充
    borderRight = UI.Panel {
        position = "absolute",
        top = 0, right = 0,
        width = borderW,
        height = 0,  -- 动态更新
        backgroundColor = COLORS.borderReady,
        pointerEvents = "none",
    }

    -- 下边框：从右到左填充
    borderBottom = UI.Panel {
        position = "absolute",
        bottom = 0, right = 0,
        width = 0,   -- 动态更新
        height = borderW,
        backgroundColor = COLORS.borderReady,
        pointerEvents = "none",
    }

    -- 左边框：从下到上填充
    borderLeft = UI.Panel {
        position = "absolute",
        bottom = 0, left = 0,
        width = borderW,
        height = 0,  -- 动态更新
        backgroundColor = COLORS.borderReady,
        pointerEvents = "none",
    }

    -- ── 顶部内高光 ──
    local highlightBar = UI.Panel {
        position = "absolute",
        top = borderW, left = borderW, right = borderW,
        height = 3,
        backgroundGradient = {
            type = "linear",
            direction = "to-bottom",
            from = COLORS.innerHighlight,
            to = { COLORS.innerHighlight[1], COLORS.innerHighlight[2], COLORS.innerHighlight[3], 0 },
        },
        pointerEvents = "none",
    }

    -- ── 底部内阴影 ──
    local shadowBar = UI.Panel {
        position = "absolute",
        bottom = borderW, left = borderW, right = borderW,
        height = 4,
        backgroundGradient = {
            type = "linear",
            direction = "to-top",
            from = COLORS.innerShadow,
            to = { COLORS.innerShadow[1], COLORS.innerShadow[2], COLORS.innerShadow[3], 0 },
        },
        pointerEvents = "none",
    }

    -- ── 按钮文字 ──
    btnLabel = UI.Label {
        id = "dropBtnLabel",
        text = text,
        fontSize = fontSize,
        fontWeight = "bold",
        fontColor = COLORS.textReady,
        textAlign = "center",
        textShadow = { x = 0, y = 2, blur = 0, color = COLORS.textShadow },
        pointerEvents = "none",
    }

    -- ── 内层面板（背景 + 文字） ──
    innerPanel = UI.Panel {
        id = "dropInner",
        position = "absolute",
        top = borderW, left = borderW, right = borderW, bottom = borderW,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = COLORS.bgReady,
        overflow = "hidden",
        pointerEvents = "none",
        children = { btnLabel },
    }

    -- 周长比例，用于分段
    local perim = 2 * (innerW + innerH)
    local fracTop    = innerW / perim
    local fracRight  = innerH / perim
    local fracBottom = innerW / perim
    -- fracLeft = 剩余

    -- 更新边框填充的内部方法
    local function UpdateBorderSegments(progress)
        progress = math.max(0, math.min(1, progress))

        -- 段1：上边框（0 ~ fracTop）
        local topProg = math.min(progress / fracTop, 1)
        borderTop:SetStyle({ width = math.floor(innerW * topProg) })

        -- 段2：右边框（fracTop ~ fracTop+fracRight）
        local rightStart = fracTop
        local rightProg = math.max(0, math.min((progress - rightStart) / fracRight, 1))
        borderRight:SetStyle({ height = math.floor(innerH * rightProg) })

        -- 段3：下边框（fracTop+fracRight ~ fracTop+fracRight+fracBottom）
        local bottomStart = fracTop + fracRight
        local bottomProg = math.max(0, math.min((progress - bottomStart) / fracBottom, 1))
        borderBottom:SetStyle({ width = math.floor(innerW * bottomProg) })

        -- 段4：左边框（剩余）
        local leftStart = fracTop + fracRight + fracBottom
        local leftFrac = 1 - leftStart
        local leftProg = 0
        if leftFrac > 0 then
            leftProg = math.max(0, math.min((progress - leftStart) / leftFrac, 1))
        end
        borderLeft:SetStyle({ height = math.floor(innerH * leftProg) })
    end

    -- ── 外层面板 ──
    outerPanel = UI.Panel {
        id = "dropButton",
        width = btnWidth,
        height = btnHeight,
        -- 暗底作为边框"未填充"的背景色
        backgroundColor = COLORS.borderDim,
        transition = "scale 0.08s easeOut, opacity 0.1s easeOut",
        pointerEvents = "auto",
        overflow = "hidden",

        -- ── Hover ──
        onPointerEnter = function(event, widget)
            if isCooling then return end
            if not isPressed then
                innerPanel:SetStyle({ backgroundColor = COLORS.bgHover })
            end
        end,

        onPointerLeave = function(event, widget)
            if isCooling then return end
            isPressed = false
            widget:SetStyle({ scale = 1.0, opacity = 1.0 })
            innerPanel:SetStyle({ backgroundColor = COLORS.bgReady })
        end,

        -- ── Press ──
        onPointerDown = function(event, widget)
            if isCooling then return end
            isPressed = true
            widget:SetStyle({ scale = 0.95, opacity = 0.85 })
            innerPanel:SetStyle({ backgroundColor = COLORS.bgPressed })
        end,

        onPointerUp = function(event, widget)
            if isCooling then return end
            if isPressed then
                isPressed = false
                widget:SetStyle({ scale = 1.0, opacity = 1.0 })
                innerPanel:SetStyle({ backgroundColor = COLORS.bgHover })
            end
        end,

        -- ── Click ──
        onClick = function(widget)
            if isCooling then return end
            if onClick then onClick() end
        end,

        children = {
            -- 边框段（绝对定位在底色之上）
            borderTop,
            borderRight,
            borderBottom,
            borderLeft,
            -- 内容区（绝对定位在边框之上）
            innerPanel,
            highlightBar,
            shadowBar,
        },
    }

    -- 初始：边框全满
    UpdateBorderSegments(1)

    -- ── 公开方法 ──

    --- 更新冷却状态（每帧调用）
    --- @param progress number 0~1，1=冷却完成/就绪
    function outerPanel:UpdateCooldown(progress)
        progress = math.max(0, math.min(1, progress or 1))

        -- 边框填充
        UpdateBorderSegments(progress)

        -- 冷却状态切换
        local nowCooling = progress < 1
        if nowCooling ~= isCooling then
            isCooling = nowCooling
            if isCooling then
                -- 进入冷却：变灰
                innerPanel:SetStyle({ backgroundColor = COLORS.bgCooldown })
                btnLabel:SetStyle({ fontColor = COLORS.textCooldown })
            else
                -- 冷却结束：恢复
                innerPanel:SetStyle({ backgroundColor = COLORS.bgReady })
                btnLabel:SetStyle({ fontColor = COLORS.textReady })
            end
        end

        lastProgress = progress
    end

    --- 设置按钮文字
    function outerPanel:SetText(newText)
        if btnLabel then
            btnLabel:SetStyle({ text = newText })
        end
    end

    return outerPanel
end

return M
