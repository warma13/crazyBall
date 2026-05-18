-- ============================================================================
-- Profiler.lua - 轻量级逐帧性能分析器
-- 使用引擎高精度计时器 GetTime():GetElapsedTime()
-- ============================================================================

local M = {}

-- ---- 配置 ----
local HISTORY_LEN   = 60     -- 采样 60 帧取平均
local UPDATE_INTERVAL = 0.5  -- 每 0.5 秒刷新显示数据

-- ---- 内部状态 ----
local sections = {}       -- { [name] = { startT, history[], histIdx } }
local sectionOrder = {}   -- 保持插入顺序
local frameStart = 0
local frameTimes = {}     -- 最近 HISTORY_LEN 帧的总帧时间
local frameIdx = 0
local frameAvg = 0
local fps = 0

-- GC 跟踪
local gcPrev = 0
local gcPerFrame = 0      -- KB/帧
local gcHistory = {}
local gcIdx = 0

-- 刷新计时
local refreshTimer = 0
local displayData = {}    -- 快照：每次刷新时复制

-- 是否启用
M.enabled = true

--- 高精度时钟：引擎 wall-clock 秒（浮点，亚毫秒精度）
local function now()
    return GetTime():GetElapsedTime()
end

--- 帧开始时调用
function M.BeginFrame()
    if not M.enabled then return end
    frameStart = now()
    gcPrev = collectgarbage("count")
    for _, sec in pairs(sections) do
        sec.startT = 0
    end
end

--- 帧结束时调用
function M.EndFrame(dt)
    if not M.enabled then return end

    -- 用引擎 dt 作为帧时间（最准确，包含渲染等待）
    frameIdx = (frameIdx % HISTORY_LEN) + 1
    frameTimes[frameIdx] = dt

    -- Lua 侧逻辑耗时（不含渲染等待）
    local luaElapsed = now() - frameStart

    -- GC 增量
    local gcNow = collectgarbage("count")
    local gcDelta = gcNow - gcPrev
    if gcDelta < 0 then gcDelta = 0 end
    gcIdx = (gcIdx % HISTORY_LEN) + 1
    gcHistory[gcIdx] = gcDelta

    -- 定时刷新显示数据
    refreshTimer = refreshTimer + dt
    if refreshTimer >= UPDATE_INTERVAL then
        refreshTimer = 0
        M._refreshDisplay(luaElapsed)
    end
end

--- 标记一个区段的开始
function M.Begin(name)
    if not M.enabled then return end
    local sec = sections[name]
    if not sec then
        sec = { startT = 0, history = {}, histIdx = 0 }
        sections[name] = sec
        sectionOrder[#sectionOrder + 1] = name
    end
    sec.startT = now()
end

--- 标记一个区段的结束
function M.End(name)
    if not M.enabled then return end
    local sec = sections[name]
    if not sec or sec.startT == 0 then return end
    local elapsed = now() - sec.startT
    sec.histIdx = (sec.histIdx % HISTORY_LEN) + 1
    sec.history[sec.histIdx] = elapsed
    sec.startT = 0
end

--- 内部：刷新显示快照
function M._refreshDisplay(luaElapsed)
    -- 帧时间平均（用引擎 dt）
    local fSum = 0
    local fN = 0
    for i = 1, HISTORY_LEN do
        if frameTimes[i] then
            fSum = fSum + frameTimes[i]
            fN = fN + 1
        end
    end
    if fN > 0 then
        frameAvg = fSum / fN
        fps = 1.0 / frameAvg
    end

    -- GC 平均
    local gSum = 0
    local gN = 0
    for i = 1, HISTORY_LEN do
        if gcHistory[i] then
            gSum = gSum + gcHistory[i]
            gN = gN + 1
        end
    end
    gcPerFrame = gN > 0 and (gSum / gN) or 0

    -- 各区段平均
    displayData = {}
    local sectionTotalMs = 0
    for _, name in ipairs(sectionOrder) do
        local sec = sections[name]
        local hSum = 0
        local hN = 0
        for i = 1, HISTORY_LEN do
            if sec.history[i] then
                hSum = hSum + sec.history[i]
                hN = hN + 1
            end
        end
        local avg = hN > 0 and (hSum / hN) or 0
        local ms = avg * 1000
        sectionTotalMs = sectionTotalMs + ms
        displayData[#displayData + 1] = { name = name, ms = ms, pct = 0 }
    end

    -- 占比 = 区段耗时 / 帧总时间
    local totalMs = frameAvg * 1000
    if totalMs > 0 then
        for _, d in ipairs(displayData) do
            d.pct = d.ms / totalMs * 100
        end
    end
end

--- 绘制性能叠加层
function M.DrawOverlay(vg, x, y)
    if not M.enabled then return end

    local S = require("State").S
    local lineH = S(14)
    local padX = S(8)
    local padY = S(6)
    local barMaxW = S(80)

    local rowCount = #displayData + 3  -- header + frame + gc + sections
    local panelW = S(210)
    local panelH = padY * 2 + lineH * (rowCount + 0.5)

    -- 半透明背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, panelW, panelH, S(4))
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 200))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, S(11))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    local cy = y + padY + lineH / 2

    -- FPS / 帧时间
    local fpsColor
    if fps >= 55 then
        fpsColor = nvgRGBA(100, 255, 100, 255)
    elseif fps >= 30 then
        fpsColor = nvgRGBA(255, 220, 60, 255)
    else
        fpsColor = nvgRGBA(255, 80, 80, 255)
    end
    nvgFillColor(vg, fpsColor)
    nvgText(vg, x + padX, cy,
        string.format("FPS: %.0f  (%.2fms/帧)", fps, frameAvg * 1000))
    cy = cy + lineH

    -- GC
    local gcColor
    if gcPerFrame < 1 then
        gcColor = nvgRGBA(100, 255, 100, 255)
    elseif gcPerFrame < 5 then
        gcColor = nvgRGBA(255, 220, 60, 255)
    else
        gcColor = nvgRGBA(255, 80, 80, 255)
    end
    nvgFillColor(vg, gcColor)
    nvgText(vg, x + padX, cy,
        string.format("GC: %.1f KB/帧  (%.0f KB)", gcPerFrame, collectgarbage("count")))
    cy = cy + lineH

    -- 分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + padX, cy)
    nvgLineTo(vg, x + panelW - padX, cy)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
    cy = cy + lineH * 0.7

    -- 各区段
    for _, d in ipairs(displayData) do
        local rowColor
        if d.ms < 1 then
            rowColor = nvgRGBA(180, 220, 180, 255)
        elseif d.ms < 3 then
            rowColor = nvgRGBA(255, 220, 100, 255)
        else
            rowColor = nvgRGBA(255, 100, 80, 255)
        end
        nvgFillColor(vg, rowColor)

        local label = string.format("%-12s %5.2fms %4.0f%%", d.name, d.ms, d.pct)
        nvgText(vg, x + padX, cy, label)

        -- 小横条（16.67ms = 60fps 满条）
        local barW = math.min(barMaxW, barMaxW * (d.ms / 16.67))
        if barW > 0.5 then
            nvgBeginPath(vg)
            nvgRect(vg, x + panelW - padX - barMaxW, cy - lineH * 0.25, barW, lineH * 0.35)
            nvgFillColor(vg, rowColor)
            nvgFill(vg)
        end

        cy = cy + lineH
    end
end

return M
