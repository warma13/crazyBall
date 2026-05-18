-- ============================================================================
-- Renderer.lua - NanoVG 渲染
-- ============================================================================

local Config = require("Config")
local BigNum = require("BigNum")
local State = require("State")
local Slots = require("Slots")
local Upgrades = require("Upgrades")
local IdleMode = require("IdleMode")

local CONFIG = Config.CONFIG
local gameState = State.gameState

local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_random = math.random
local math_sin = math.sin
local math_cos = math.cos
local math_abs = math.abs
local math_ceil = math.ceil

local Profiler = require("Profiler")
local Runes = require("Runes")

local M = {}

-- 缓存的 TopBar 文本（避免每帧 BigNum.format）
local cachedCoinStr = ""
local cachedGemStr = ""
local cachedProgressStr = ""
local cachedCoinsRef = nil    -- 上次格式化时的 coins 值引用
local cachedGemsRef = -1
local cachedEarnedRef = nil
local cachedTargetRef = nil

--- 更新缓存的格式化字符串（仅值变化时重新格式化）
local function UpdateCachedStrings()
    if gameState.coins ~= cachedCoinsRef then
        cachedCoinsRef = gameState.coins
        cachedCoinStr = State.FormatNumber(gameState.coins)
    end
    local gems = State.GetGems()
    if gems ~= cachedGemsRef then
        cachedGemsRef = gems
        cachedGemStr = tostring(gems)
    end
    if gameState.roundEarned ~= cachedEarnedRef or gameState.roundTarget ~= cachedTargetRef then
        cachedEarnedRef = gameState.roundEarned
        cachedTargetRef = gameState.roundTarget
        cachedProgressStr = State.FormatNumber(gameState.roundEarned)
            .. "/" .. State.FormatNumber(gameState.roundTarget)
    end
end

-- 菜单背景装饰圆点预计算（避免每帧 math.randomseed + 40次 math.random）
local menuDots = nil  -- 延迟初始化（需要 S() 和屏幕尺寸）
local menuDotsW, menuDotsH = 0, 0  -- 上次计算时的屏幕尺寸

-- 菜单图片资源（延迟加载）
local imgMenuBg = nil       -- 主页背景图
local imgBtnBlue = nil      -- 蓝色按钮边框（新游戏、继续游戏）
local imgBtnPurple = nil    -- 紫色按钮边框（符文）
local imgBtnGreen = nil     -- 绿色按钮边框（放置模式）

-- 按钮点击区域（供 main.lua 检测）
M.lbBtnRect = nil       -- { x, y, w, h } 逻辑坐标
M.settingsBtnRect = nil  -- 设置按钮区域

-- 图标句柄（延迟加载）
local imgCoin = nil
local imgGem = nil
local imgGold = nil  -- 金币图标（idle 模式用）
local imgCurrBar = nil  -- 货币栏背景图
local imgPeg = nil       -- 撞钉图片
local imgArcade = nil    -- 街机边框


-- 球皮肤图片缓存 { [skinKey] = nvgImageHandle }
local ballSkinImages = {}

-- idle 钉颜色组（静态，避免每帧分配）
local _idleColorGroups = {
    { cond = "burning",  r = 255, g = 100, b = 40 },
    { cond = "charged",  r = 80,  g = 240, b = 200 },
    { cond = "marked",   r = 210, g = 170, b = 255 },
    { cond = "gold",     r = 230, g = 200, b = 120 },
    { cond = "effect",   r = 200, g = 215, b = 235 },
    { cond = "default",  r = 180, g = 200, b = 220 },
}

--- 缩放快捷引用（每帧更新后使用）
local S = State.S

-- 水印信息
local GAME_VERSION = "v1.0.0"
M.GAME_VERSION = GAME_VERSION
local cachedUidStr = nil  -- 延迟获取

--- 绘制全局水印（右上角用户ID）
--- 左下角版本号通过 UI 层显示（避免被 UI 面板遮挡）
local function DrawWatermark(vg, w, h)
    -- 延迟获取用户ID（clientCloud 可能尚未初始化）
    if not cachedUidStr then
        ---@diagnostic disable-next-line: undefined-global
        if clientCloud and clientCloud.userId then
            cachedUidStr = "ID:" .. tostring(clientCloud.userId)
        else
            cachedUidStr = ""
        end
    end

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, S(9))

    -- 右上角：用户ID
    if cachedUidStr ~= "" then
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(180, 190, 210, 100))
        nvgText(vg, w - S(4), S(3), cachedUidStr, nil)
    end
end

--- NanoVG 渲染主入口
function M.HandleNanoVGRender(eventType, eventData)
    local vg = State.vg
    if not vg then return end

    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local w = physW / dpr
    local h = physH / dpr

    -- 每帧更新缩放系数
    State.UpdateUIScale()
    S = State.S

    -- 延迟加载图标（只创建一次）
    if not imgCoin then
        imgCoin = nvgCreateImage(vg, "image/gold_coin.png", 0)
    end
    if not imgGem then
        imgGem = nvgCreateImage(vg, "image/gem_20260328213704.png", 0)
    end
    if not imgGold then
        imgGold = nvgCreateImage(vg, "image/gold_coin.png", 0)
    end
    if not imgCurrBar then
        imgCurrBar = nvgCreateImage(vg, "image/ui_currency_bar_20260518073701.png", 0)
    end
    if not imgPeg then
        imgPeg = nvgCreateImage(vg, "image/peg_20260518150745.png", 0)
    end

    nvgBeginFrame(vg, w, h, dpr)

    if gameState.gamePhase == "menu" then
        M.DrawMenuScreen(vg, w, h)
        DrawWatermark(vg, w, h)
        nvgEndFrame(vg)
        return
    end

    if gameState.gamePhase == "runes" then
        M.DrawRuneScreen(vg, w, h)
        DrawWatermark(vg, w, h)
        nvgEndFrame(vg)
        return
    end

    if gameState.gamePhase == "idle" then
        IdleMode.Render(vg, w, h)
        DrawWatermark(vg, w, h)
        nvgEndFrame(vg)
        return
    end

    if gameState.screenShake > 0 and gameState.settings.shakeEnabled then
        nvgSave(vg)
        nvgTranslate(vg, (math.random() - 0.5) * S(3), (math.random() - 0.5) * S(3))
    end

    M.DrawBackground(vg, w, h)

    -- 上半屏裁剪
    nvgSave(vg)
    nvgScissor(vg, 0, 0, w, gameState.splitY + 2)
    M.DrawBoard(vg, w, h)

    Profiler.Begin("DrawSlots")
    M.DrawSlots(vg)
    Profiler.End("DrawSlots")

    Profiler.Begin("DrawPegs")
    M.DrawPegs(vg)
    Profiler.End("DrawPegs")

    Profiler.Begin("DrawBalls")
    M.DrawBalls(vg)
    Profiler.End("DrawBalls")

    Profiler.Begin("DrawPopups")
    M.DrawPopups(vg)
    Profiler.End("DrawPopups")
    M.DrawDropZone(vg, w)
    nvgRestore(vg)

    M.DrawSplitLine(vg, w)
    Profiler.Begin("DrawTopBar")
    M.DrawTopBar(vg, w)
    Profiler.End("DrawTopBar")

    if gameState.screenShake > 0 and gameState.settings.shakeEnabled then
        nvgRestore(vg)
    end

    -- 漂浮提示文字（"时间到"）
    if gameState.failedToast and gameState.failedToast.timer > 0 then
        local t = gameState.failedToast
        local alpha = math.min(1, t.timer / 0.5) * 255
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, S(28))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 80, 80, math.floor(alpha)))
        nvgText(vg, w / 2, h * 0.35 + t.offsetY, t.text)
    end

    -- ---- 性能叠加层（已隐藏） ----
    -- Profiler.DrawOverlay(vg, S(4), S(55))

    DrawWatermark(vg, w, h)
    nvgEndFrame(vg)
end

local bgImage = nil
local BG_IMG_W, BG_IMG_H = 1080, 1935  -- 原始图片尺寸

function M.DrawBackground(vg, w, h)
    if not bgImage then
        bgImage = nvgCreateImage(vg, "image/game_bg_20260413031232.png", 0)
    end
    if bgImage and bgImage >= 0 then
        -- cover 模式：保持比例填满屏幕，居中裁剪
        local imgAspect = BG_IMG_W / BG_IMG_H
        local scrAspect = w / h
        local drawW, drawH
        if scrAspect > imgAspect then
            -- 屏幕更宽，以宽度为准
            drawW = w
            drawH = w / imgAspect
        else
            -- 屏幕更高，以高度为准
            drawH = h
            drawW = h * imgAspect
        end
        local ox = (w - drawW) / 2
        local oy = (h - drawH) / 2
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillPaint(vg, nvgImagePattern(vg, ox, oy, drawW, drawH, 0, bgImage, 1.0))
        nvgFill(vg)
    else
        -- fallback 纯色
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillPaint(vg, nvgLinearGradient(vg, 0, 0, 0, h,
            nvgRGBA(15, 20, 35, 255), nvgRGBA(10, 12, 25, 255)))
        nvgFill(vg)
    end
end

function M.DrawBoard(vg, w, h)
    -- 街机边框
    if not imgArcade then
        imgArcade = nvgCreateImage(vg, "image/arcade_3d_20260518160636.png", 0)
    end
    if imgArcade and imgArcade >= 0 then
        local bL = gameState.boardLeft
        local bR = gameState.boardRight
        local bT = gameState.boardTop
        local bB = gameState.boardBottom
        -- 边框图片比棋盘区域稍大，留出边框厚度
        local padX = S(12)
        local padTop = S(25)
        local padBot = S(12)
        local dx, dy = bL - padX, bT - padTop
        local dw, dh = (bR - bL) + padX * 2, (bB - bT) + padTop + padBot
        nvgBeginPath(vg)
        nvgRect(vg, dx, dy, dw, dh)
        nvgFillPaint(vg, nvgImagePattern(vg, dx, dy, dw, dh, 0, imgArcade, 1.0))
        nvgFill(vg)
    end
end

function M.DrawPegs(vg)
    local bs = gameState.boardScale or 1
    local pegR = CONFIG.PEG_RADIUS * bs
    local time = GetTime():GetElapsedTime()

    -- 缓存激活的弹钉效果（避免每个钉每帧查询）
    local hasGold = Upgrades.GetEffectLevel("peg_gold") > 0
    local hasMagnet = Upgrades.GetEffectLevel("peg_magnet") > 0
    local hasResonance = Upgrades.GetEffectLevel("peg_resonance") > 0
    local hasBonus = Upgrades.GetEffectLevel("peg_bonus") > 0
    local hasSpark = Upgrades.GetEffectLevel("peg_spark") > 0
    local hasCharge = Upgrades.GetEffectLevel("peg_charge") > 0
    local hasMark = Upgrades.GetEffectLevel("peg_mark") > 0
    local hasAnyEffect = hasGold or hasMagnet or hasResonance or hasBonus
        or hasSpark or hasCharge or hasMark

    -- 预计算脉冲值（所有钉共享）
    local pulse = 0.5 + 0.5 * math.sin(time * 3)
    local pulse2 = 0.5 + 0.5 * math.sin(time * 4 + 1)
    local pulse3 = 0.5 + 0.5 * math.sin(time * 2.5 + 2)
    local burnPulse = 0.6 + 0.4 * math.sin(time * 6)
    local chargePulse = 0.4 + 0.6 * math.abs(math.sin(time * 5))
    local markPulse = 0.5 + 0.5 * math.sin(time * 3.5)

    -- ====== 效果光环层（低画质完全跳过） ======
    local lowQ = State.lowQuality
    if hasAnyEffect and not lowQ then
        -- 单趟扫描收集各效果的钉子存在标志
        local hasBurning, hasCharged, hasMarked = false, false, false
        for _, peg in ipairs(gameState.pegs) do
            if peg.burning then hasBurning = true end
            if peg.chargedBy then hasCharged = true end
            if peg.markedBy then hasMarked = true end
            if hasBurning and hasCharged and hasMarked then break end
        end

        -- 灼烧外圈
        if hasBurning then
            nvgBeginPath(vg)
            for _, peg in ipairs(gameState.pegs) do
                if peg.burning then
                    nvgCircle(vg, peg.x, peg.y, pegR + S(3) * burnPulse)
                end
            end
            nvgFillColor(vg, nvgRGBA(255, 80, 20, math.floor(50 * burnPulse)))
            nvgFill(vg)
            -- 灼烧内圈
            nvgBeginPath(vg)
            for _, peg in ipairs(gameState.pegs) do
                if peg.burning then
                    nvgCircle(vg, peg.x, peg.y, pegR + S(1.5))
                end
            end
            nvgFillColor(vg, nvgRGBA(255, 140, 30, math.floor(70 * burnPulse)))
            nvgFill(vg)
        end

        -- 充能光环
        if hasCharged then
            nvgBeginPath(vg)
            for _, peg in ipairs(gameState.pegs) do
                if peg.chargedBy then
                    nvgCircle(vg, peg.x, peg.y, pegR + S(2.5) * chargePulse)
                end
            end
            nvgFillColor(vg, nvgRGBA(50, 230, 180, math.floor(50 * chargePulse)))
            nvgFill(vg)
        end

        -- 印记光环
        if hasMarked then
            nvgBeginPath(vg)
            for _, peg in ipairs(gameState.pegs) do
                if peg.markedBy then
                    nvgCircle(vg, peg.x, peg.y, pegR + S(2) * markPulse)
                end
            end
            nvgFillColor(vg, nvgRGBA(200, 150, 255, math.floor(45 * markPulse)))
            nvgFill(vg)
        end

        -- 黄金光环（全部钉统一颜色，合批）
        if hasGold then
            local goldR = pegR + S(1.5) * pulse
            nvgBeginPath(vg)
            for _, peg in ipairs(gameState.pegs) do
                nvgCircle(vg, peg.x, peg.y, goldR)
            end
            nvgFillColor(vg, nvgRGBA(255, 200, 50, math.floor(25 + 15 * pulse)))
            nvgFill(vg)
        end

        -- 磁场环（合批 stroke）
        if hasMagnet then
            local magnetR = pegR + S(2.5) * pulse2
            nvgBeginPath(vg)
            for _, peg in ipairs(gameState.pegs) do
                nvgCircle(vg, peg.x, peg.y, magnetR)
            end
            nvgStrokeColor(vg, nvgRGBA(100, 180, 255, math.floor(30 + 25 * pulse2)))
            nvgStrokeWidth(vg, S(0.8))
            nvgStroke(vg)
        end

        -- 火花点（已移除）
    end

    -- ====== 钉子本体层 ======
    local cr, cg, cb = CONFIG.PEG_HIT_COLOR[1], CONFIG.PEG_HIT_COLOR[2], CONFIG.PEG_HIT_COLOR[3]

    -- 按颜色分组渲染 idle 钉（固定颜色组，不分配表）
    -- 颜色组: 1=burning(255,100,40) 2=charged(80,240,200) 3=marked(210,170,255)
    --         4=gold(230,200,120) 5=anyEffect(200,215,235) 6=default(180,200,220)
    -- 先画所有 hit 钉
    if lowQ then
        -- 低画质：合批所有 hit 钉（统一颜色，1 个 draw call）
        local hasHit = false
        for _, peg in ipairs(gameState.pegs) do
            if peg.hitTimer > 0 then
                if not hasHit then nvgBeginPath(vg); hasHit = true end
                nvgCircle(vg, peg.x, peg.y, pegR)
            end
        end
        if hasHit then
            nvgFillColor(vg, nvgRGBA(cr, cg, cb, 220))
            nvgFill(vg)
        end
    else
        -- 高画质：逐个带外扩光环
        for _, peg in ipairs(gameState.pegs) do
            if peg.hitTimer > 0 then
                local t = peg.hitTimer / CONFIG.PEG_HIT_DURATION
                nvgBeginPath(vg)
                nvgCircle(vg, peg.x, peg.y, pegR + S(4) * t)
                nvgFillColor(vg, nvgRGBA(cr, cg, cb, math.floor(80 * t)))
                nvgFill(vg)
                nvgBeginPath(vg)
                nvgCircle(vg, peg.x, peg.y, pegR)
                nvgFillColor(vg, nvgRGBA(cr, cg, cb, math.floor(200 * t + 55)))
                nvgFill(vg)
            end
        end
    end

    -- idle 钉阴影层
    if not lowQ then
        nvgBeginPath(vg)
        for _, peg in ipairs(gameState.pegs) do
            if peg.hitTimer <= 0 then
                nvgCircle(vg, peg.x + S(1.5), peg.y + S(2), pegR * 0.95)
            end
        end
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 50))
        nvgFill(vg)
    end

    -- idle 钉：使用图片绘制
    local imgDrawR = pegR * 1.6  -- 图片含外发光，绘制尺寸比碰撞半径大
    local imgDrawD = imgDrawR * 2
    for _, peg in ipairs(gameState.pegs) do
        if peg.hitTimer <= 0 then
            local px, py = peg.x - imgDrawR, peg.y - imgDrawR
            nvgBeginPath(vg)
            nvgRect(vg, px, py, imgDrawD, imgDrawD)
            nvgFillPaint(vg, nvgImagePattern(vg, px, py, imgDrawD, imgDrawD, 0, imgPeg, 1.0))
            nvgFill(vg)
        end
    end

    if lowQ then return end
end

function M.DrawBalls(vg)
    local ballCount = #gameState.balls
    local lowQ = State.lowQuality

    -- 动态降级：球多时减少尾迹段数（≤8球=6段, ≤15球=3段, >15球=1段）
    -- 低画质：完全跳过尾迹
    local maxTrail = lowQ and 0 or (ballCount > 15 and 1 or (ballCount > 8 and 3 or 6))

    -- ====== 优化的尾迹渲染：单趟收集 + 按类型×age 合批 ======
    -- 替代原来的 O(ages × types × balls) 三重循环
    -- 新方案：O(balls × maxTrail) + O(presentTypes × ages) 渲染
    if maxTrail > 0 then
        -- 第1步：单趟收集每种球类型在场上是否存在（位图）
        local typesPresent = {}  -- { typeIndex = true }
        local typeCount = 0
        for bi = 1, ballCount do
            local ball = gameState.balls[bi]
            local ti = ball.typeIndex
            if not typesPresent[ti] then
                typesPresent[ti] = true
                typeCount = typeCount + 1
            end
        end

        -- 第2步：只遍历实际在场的类型（通常 1-3 种而非 13 种）
        for bti in pairs(typesPresent) do
            local gc = Config.BALL_TYPES[bti].glowColor
            for age = maxTrail, 1, -1 do
                local hasAny = false
                local alpha = 0
                for bi = 1, ballCount do
                    local ball = gameState.balls[bi]
                    if ball.typeIndex == bti then
                        local trailLen = ball.trailLen or 0
                        local drawLen = trailLen < maxTrail and trailLen or maxTrail
                        if drawLen >= age then
                            if not hasAny then
                                nvgBeginPath(vg)
                                hasAny = true
                            end
                            local invLen = 1 / drawLen
                            alpha = math_floor(60 * (1 - age * invLen))
                            local trailHead = ball.trailHead or 0
                            local j = trailLen - age + 1
                            local idx = (trailHead - trailLen + j - 1) % 6 + 1
                            local tr = ball.trail[idx]
                            if tr then
                                local r = ball.radius * (1 - age * 0.1)
                                if r > 0 then
                                    nvgCircle(vg, tr.x, tr.y, r)
                                end
                            end
                        end
                    end
                end
                if hasAny then
                    nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], alpha))
                    nvgFill(vg)
                end
            end
        end
    end

    -- ====== 球本体 ======
    if lowQ then
        -- 低画质：按类型合批纯色填充（跳过径向渐变），皮肤球仍逐个绘制
        -- 先处理皮肤球（逐个，图片纹理 GPU 开销小）
        for _, ball in ipairs(gameState.balls) do
            local bt = Config.BALL_TYPES[ball.typeIndex]
            local activeSkin = gameState.ballSkins[ball.typeIndex] or "default"
            if activeSkin ~= "default" and bt.skinKey then
                local skinImg = ballSkinImages[bt.skinKey]
                if skinImg == nil then
                    skinImg = nvgCreateImage(vg, Config.GetBallSkinImage(bt.skinKey), 0)
                    ballSkinImages[bt.skinKey] = skinImg
                end
                if skinImg and skinImg >= 0 then
                    local r = ball.radius
                    local d = r * 2
                    nvgBeginPath(vg)
                    nvgCircle(vg, ball.x, ball.y, r)
                    nvgFillPaint(vg, nvgImagePattern(vg, ball.x - r, ball.y - r, d, d, 0, skinImg, 1.0))
                    nvgFill(vg)
                end
            end
        end
        -- 再按类型合批默认球（纯色，无渐变）
        for bti = 1, #Config.BALL_TYPES do
            local bt = Config.BALL_TYPES[bti]
            local activeSkin = gameState.ballSkins[bti] or "default"
            if activeSkin == "default" or not bt.skinKey then
                local hasAny = false
                for bi = 1, ballCount do
                    local ball = gameState.balls[bi]
                    if ball.typeIndex == bti then
                        if not hasAny then nvgBeginPath(vg); hasAny = true end
                        nvgCircle(vg, ball.x, ball.y, ball.radius)
                    end
                end
                if hasAny then
                    nvgFillColor(vg, nvgRGBA(bt.color[1], bt.color[2], bt.color[3], bt.color[4]))
                    nvgFill(vg)
                end
            end
        end
    else
        -- 高画质：逐个球渲染（皮肤图片 or 径向渐变）
        for _, ball in ipairs(gameState.balls) do
            local bt = Config.BALL_TYPES[ball.typeIndex]
            local activeSkin = gameState.ballSkins[ball.typeIndex] or "default"
            if activeSkin ~= "default" and bt.skinKey then
                local skinImg = ballSkinImages[bt.skinKey]
                if skinImg == nil then
                    skinImg = nvgCreateImage(vg, Config.GetBallSkinImage(bt.skinKey), 0)
                    ballSkinImages[bt.skinKey] = skinImg
                end
                if skinImg and skinImg >= 0 then
                    local r = ball.radius
                    local d = r * 2
                    nvgBeginPath(vg)
                    nvgCircle(vg, ball.x, ball.y, r)
                    nvgFillPaint(vg, nvgImagePattern(vg, ball.x - r, ball.y - r, d, d, 0, skinImg, 1.0))
                    nvgFill(vg)
                end
            else
                nvgBeginPath(vg)
                nvgCircle(vg, ball.x, ball.y, ball.radius)
                nvgFillPaint(vg, nvgRadialGradient(vg,
                    ball.x - S(2), ball.y - S(2), 1, ball.radius,
                    nvgRGBA(255, 255, 255, 180),
                    nvgRGBA(bt.color[1], bt.color[2], bt.color[3], bt.color[4])))
                nvgFill(vg)
            end
        end
    end
end

-- 口袋底图缓存
local imgSlotTray = nil

function M.DrawSlots(vg)
    local fontNormal = State.fontNormal
    local slotCount = #gameState.slots
    local slotW = gameState.slotWidth
    local bs = gameState.boardScale or 1
    local slotY = gameState.contentBottom - CONFIG.SLOT_HEIGHT * bs
    local slotH = CONFIG.SLOT_HEIGHT * bs
    local time = GetTime():GetElapsedTime()
    local lowQ = State.lowQuality

    -- 放置模式 per-slot 填充进度需要的数据
    local isIdle = (gameState.gamePhase == "idle")

    -- ===== 口袋底图（图片） =====
    if not imgSlotTray then
        imgSlotTray = nvgCreateImage(vg, "image/slot_tray_wide_trimmed.png", 0)
    end
    if imgSlotTray and imgSlotTray >= 0 then
        -- 拉伸到和边框一样宽（boardLeft/Right）
        local bL = gameState.boardLeft
        local bR = gameState.boardRight
        local dw = bR - bL
        local dh = slotH
        local dx = bL
        local dy = gameState.contentBottom - dh
        nvgBeginPath(vg)
        nvgRect(vg, dx, dy, dw, dh)
        nvgFillPaint(vg, nvgImagePattern(vg, dx, dy, dw, dh, 0, imgSlotTray, 1.0))
        nvgFill(vg)
    end

    -- ===== 放置模式：per-slot 填充进度 =====
    local edges = gameState.slotEdges
    local centers = gameState.slotCenters
    if isIdle and edges then
        if lowQ then
            nvgBeginPath(vg)
            for i = 1, slotCount do
                local slot = gameState.slots[i]
                local drops = slot.drops or 0
                local req = IdleMode.GetSlotUpgradeRequirement(slot.level or 1)
                local pct = drops / req
                if pct > 1 then pct = 1 end
                if pct > 0 then
                    local eL = edges[i]
                    local eR = edges[i + 1]
                    local fillH = slotH * pct
                    nvgRect(vg, eL + 1, slotY + slotH - fillH, eR - eL - 2, fillH)
                end
            end
            nvgFillColor(vg, nvgRGBA(80, 200, 120, 100))
            nvgFill(vg)
        else
            for i = 1, slotCount do
                local slot = gameState.slots[i]
                local drops = slot.drops or 0
                local req = IdleMode.GetSlotUpgradeRequirement(slot.level or 1)
                local pct = drops / req
                if pct > 1 then pct = 1 end
                if pct > 0 then
                    local eL = edges[i]
                    local eR = edges[i + 1]
                    local fillH = slotH * pct
                    nvgBeginPath(vg)
                    nvgRect(vg, eL + 1, slotY + slotH - fillH, eR - eL - 2, fillH)
                    local glowAlpha = math_floor(120 + 40 * math_sin(time * 3 + i))
                    nvgFillPaint(vg, nvgLinearGradient(vg,
                        eL, slotY + slotH - fillH, eL, slotY + slotH,
                        nvgRGBA(80, 220, 140, glowAlpha),
                        nvgRGBA(60, 180, 100, math_floor(glowAlpha * 0.6))))
                    nvgFill(vg)
                end
            end
        end
    end

    -- ===== 倍率文字 =====
    nvgFontFaceId(vg, fontNormal)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for i = 1, slotCount do
        local slot = gameState.slots[i]
        local slotMult = Slots.GetSlotMult(slot)
        local label = Slots.GetSlotLabel(slot)
        local cx = centers and centers[i] or (gameState.boardLeft + (i - 0.5) * slotW)
        local fontSize = S(13)
        if slotMult >= 100 then fontSize = S(9)
        elseif slotMult >= 10 then fontSize = S(11)
        end
        nvgFontSize(vg, fontSize)
        if not lowQ and slotMult >= 50 then
            local pulse = 0.7 + 0.3 * math_sin(time * 5)
            nvgFillColor(vg, nvgRGBA(255, 255, 100, math_floor(255 * pulse)))
        elseif not lowQ and slotMult >= 10 then
            local pulse = 0.7 + 0.3 * math_sin(time * 4)
            nvgFillColor(vg, nvgRGBA(255, 230, 50, math_floor(255 * pulse)))
        else
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
        end
        nvgText(vg, cx, slotY + slotH / 2, label, nil)
    end
end

function M.DrawPopups(vg)
    local fontNormal = State.fontNormal
    local GRAVITY = 150  -- 抛物线重力（未缩放像素/s²）
    for _, p in ipairs(gameState.popups) do
        local t = p.timer / CONFIG.POPUP_DURATION
        local alpha = math_floor(255 * t)

        -- 位置计算
        local px, py
        if p.iconType then
            -- 抛物线轨迹
            local elapsed = p.elapsed or 0
            local vx = p.vx or 0
            local vy = p.vy or 0
            px = p.x + S(vx * elapsed)
            py = p.y + S(vy * elapsed + 0.5 * GRAVITY * elapsed * elapsed)
        else
            -- 旧行为：线性上升
            local rise = S(CONFIG.POPUP_RISE) * (1 - t)
            px = p.x
            py = p.y - rise
        end

        nvgFontFaceId(vg, fontNormal)
        nvgFontSize(vg, S(p.fontSize or 14))

        if p.iconType then
            -- 新：图标 + 数字渲染
            local iconImg = nil
            if p.iconType == "coin" then
                iconImg = imgCoin
            elseif p.iconType == "ball" then
                local sk = p.skinKey or "iron"
                iconImg = ballSkinImages[sk]
                if not iconImg then
                    iconImg = nvgCreateImage(vg, Config.GetBallSkinImage(sk), 0)
                    ballSkinImages[sk] = iconImg
                end
            elseif p.iconType == "gold" then
                iconImg = imgGold
            elseif p.iconType == "gem" then
                iconImg = imgGem
            end

            local iconSz = S((p.fontSize or 14) + 4)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local advance = nvgTextBounds(vg, 0, 0, p.text)
            local totalW = iconSz + S(3) + advance
            local startX = px - totalW / 2

            if iconImg and iconImg >= 0 then
                local paint = nvgImagePattern(vg, startX, py - iconSz / 2, iconSz, iconSz, 0, iconImg, alpha / 255)
                nvgBeginPath(vg)
                nvgRoundedRect(vg, startX, py - iconSz / 2, iconSz, iconSz, iconSz / 2)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            end

            nvgFillColor(vg, nvgRGBA(p.color[1], p.color[2], p.color[3], alpha))
            nvgText(vg, startX + iconSz + S(3), py, p.text, nil)
        elseif p.icon == "gem" and imgGem and imgGem >= 0 then
            -- 旧版宝石图标渲染
            local iconSz = S((p.fontSize or 14) + 2)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            local advance = nvgTextBounds(vg, 0, 0, p.text)
            local totalW = iconSz + S(3) + advance
            local startX = px - totalW / 2

            local paint = nvgImagePattern(vg, startX, py - iconSz / 2, iconSz, iconSz, 0, imgGem, alpha / 255)
            nvgBeginPath(vg)
            nvgRect(vg, startX, py - iconSz / 2, iconSz, iconSz)
            nvgFillPaint(vg, paint)
            nvgFill(vg)

            nvgFillColor(vg, nvgRGBA(p.color[1], p.color[2], p.color[3], alpha))
            nvgText(vg, startX + iconSz + S(3), py, p.text, nil)
        else
            -- 旧版纯文字渲染
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(p.color[1], p.color[2], p.color[3], alpha))
            nvgText(vg, px, py, p.text, nil)
        end
    end
end

function M.DrawDropZone(vg, w)
    -- 已移除顶部投放提示
end

function M.DrawSplitLine(vg, w)
    local sy = gameState.splitY
    nvgBeginPath(vg)
    nvgRect(vg, 0, sy - S(2), w, S(5))
    nvgFillPaint(vg, nvgLinearGradient(vg, 0, sy - S(2), 0, sy + S(3),
        nvgRGBA(60, 80, 140, 0), nvgRGBA(80, 110, 180, 150)))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, sy)
    nvgLineTo(vg, w, sy)
    nvgStrokeColor(vg, nvgRGBA(90, 120, 180, 220))
    nvgStrokeWidth(vg, S(1.5))
    nvgStroke(vg)
end

function M.DrawTopBar(vg, w)
    UpdateCachedStrings()
    local fontNormal = State.fontNormal
    local bs = gameState.boardScale or 1
    local barH = CONFIG.BOARD_MARGIN_TOP * bs
    local padX = S(14)

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, barH)
    nvgFillPaint(vg, nvgLinearGradient(vg, 0, 0, 0, barH,
        nvgRGBA(20, 25, 50, 240), nvgRGBA(15, 20, 40, 200)))
    nvgFill(vg)

    nvgFontFaceId(vg, fontNormal)

    local textY = S(20)
    local barY = S(40)
    local barH2 = S(10)
    local iconSize = S(16)

    -- ==== 五列等宽布局: 货币 | 排行榜 | 轮次 | 设置 | 目标 ====
    local colW = w / 5
    local contentTop = barY
    local colCenterY = contentTop / 2

    -- 绘制列分隔线（4 条）
    for i = 1, 4 do
        local lx = colW * i
        nvgBeginPath(vg)
        nvgMoveTo(vg, lx, S(6))
        nvgLineTo(vg, lx, contentTop - S(4))
        nvgStrokeColor(vg, nvgRGBA(60, 75, 120, 140))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
    end

    -- ---- 列1: 货币（金币 + 宝石）用背景图样式 ----
    -- 背景图原图 430×96，圆直径≈图高
    if imgCurrBar and imgCurrBar >= 0 then
        local barImgH = S(16)  -- 每个货币栏高度
        local barImgW = barImgH * 430 / 96  -- 保持图片比例
        local barX = S(4)
        local circleW = barImgH  -- 圆形区域宽度=高度
        local coinIconSz = barImgH * 0.55

        -- 金币栏
        local barY1 = textY - S(4) - barImgH / 2
        local paint1 = nvgImagePattern(vg, barX, barY1, barImgW, barImgH, 0, imgCurrBar, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY1, barImgW, barImgH, barImgH * 0.1)
        nvgFillPaint(vg, paint1)
        nvgFill(vg)

        -- 金币图标（圆形区域居中）
        if imgCoin and imgCoin >= 0 then
            local cix = barX + (circleW - coinIconSz) / 2
            local ciy = barY1 + (barImgH - coinIconSz) / 2
            local cp = nvgImagePattern(vg, cix, ciy, coinIconSz, coinIconSz, 0, imgCoin, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, cix, ciy, coinIconSz, coinIconSz)
            nvgFillPaint(vg, cp)
            nvgFill(vg)
        end

        -- 金币数字
        nvgFontSize(vg, S(11))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 60, 255))
        nvgText(vg, barX + circleW + S(2), barY1 + barImgH / 2, cachedCoinStr, nil)

        -- 宝石栏
        local barY2 = textY + S(10) - barImgH / 2
        local paint2 = nvgImagePattern(vg, barX, barY2, barImgW, barImgH, 0, imgCurrBar, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY2, barImgW, barImgH, barImgH * 0.1)
        nvgFillPaint(vg, paint2)
        nvgFill(vg)

        -- 宝石图标
        if imgGem and imgGem >= 0 then
            local gix = barX + (circleW - coinIconSz) / 2
            local giy = barY2 + (barImgH - coinIconSz) / 2
            local gp = nvgImagePattern(vg, gix, giy, coinIconSz, coinIconSz, 0, imgGem, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, gix, giy, coinIconSz, coinIconSz)
            nvgFillPaint(vg, gp)
            nvgFill(vg)
        end

        -- 宝石数字
        nvgFillColor(vg, nvgRGBA(200, 230, 255, 255))
        nvgText(vg, barX + circleW + S(2), barY2 + barImgH / 2, cachedGemStr, nil)
    end

    -- ---- 列2: 排行榜 ----
    local col2Center = colW + colW / 2
    nvgFontSize(vg, S(13))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 215, 60, 230))
    nvgText(vg, col2Center, colCenterY, "排行榜", nil)

    M.lbBtnRect = { x = colW, y = 0, w = colW, h = barH }

    -- ---- 列3: 轮次 + 计时器 ----
    local col3Center = colW * 2 + colW / 2
    local timeLeft = math.max(0, math.ceil(gameState.roundTimeLeft))
    local timeStr = string.format("第%d轮  %ds", gameState.round, timeLeft)

    local tr, tg, tb
    if timeLeft > 30 then
        tr, tg, tb = 100, 230, 130
    elseif timeLeft > 10 then
        tr, tg, tb = 255, 210, 60
    else
        local elapsed = GetTime():GetElapsedTime()
        local pulse = 0.5 + 0.5 * math.sin(elapsed * 6)
        tr = 255
        tg = math.floor(60 * pulse)
        tb = math.floor(60 * pulse)
    end

    nvgFontSize(vg, S(14))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(tr, tg, tb, 255))
    nvgText(vg, col3Center, textY, timeStr, nil)

    -- ---- 列4: 设置按钮 ----
    local col4Center = colW * 3 + colW / 2
    local settBtnSize = S(22)
    local settBtnY = (contentTop - settBtnSize) / 2

    nvgFontSize(vg, S(12))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 210, 240, 240))
    nvgText(vg, col4Center, settBtnY + settBtnSize / 2, "⚙ 设置", nil)

    M.settingsBtnRect = { x = colW * 3, y = 0, w = colW, h = contentTop }

    -- ==== 进度条 ====
    local progress = math.min(1.0, BigNum.toNumber(gameState.roundEarned / math.max(BigNum.new(1), gameState.roundTarget)))
    local barW = w - padX * 2

    nvgBeginPath(vg)
    nvgRoundedRect(vg, padX, barY, barW, barH2, S(4))
    nvgFillColor(vg, nvgRGBA(30, 35, 55, 200))
    nvgFill(vg)

    if progress > 0 then
        local fillW = math.max(barH2, barW * progress)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, padX, barY, fillW, barH2, S(4))
        nvgFillPaint(vg, nvgLinearGradient(vg,
            padX, barY, padX + fillW, barY,
            nvgRGBA(60, 120, 220, 230),
            nvgRGBA(100, 220, 140, 230)))
        nvgFill(vg)
    end

    nvgBeginPath(vg)
    nvgRoundedRect(vg, padX, barY, barW, barH2, S(4))
    nvgStrokeColor(vg, nvgRGBA(70, 90, 140, 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 进度条中间文字：当前分/目标分
    local isDone = gameState.roundEarned >= gameState.roundTarget
    nvgFontSize(vg, S(10))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, isDone
        and nvgRGBA(100, 255, 140, 255)
        or  nvgRGBA(230, 235, 250, 240))
    nvgText(vg, padX + barW * 0.5, barY + barH2 * 0.5, cachedProgressStr, nil)

end

-- ============================================================================
-- 符文图标缓存 { [path] = nvgImageHandle }
-- ============================================================================
local runeIconCache = {}

--- 获取或创建符文图标 nvg handle
local function GetRuneIcon(vg, path)
    if not runeIconCache[path] then
        runeIconCache[path] = nvgCreateImage(vg, path, 0)
    end
    return runeIconCache[path]
end

-- ============================================================================
-- 开始界面
-- ============================================================================
function M.DrawMenuScreen(vg, w, h)
    local fontNormal = State.fontNormal
    local time = GetTime():GetElapsedTime()

    -- 延迟加载菜单图片资源
    if not imgMenuBg then
        imgMenuBg = nvgCreateImage(vg, "image/主页背景图_20260518175707.png", 0)
    end
    if not imgBtnBlue then
        imgBtnBlue = nvgCreateImage(vg, "image/btn_blue_20260518181012.png", 0)
    end
    if not imgBtnPurple then
        imgBtnPurple = nvgCreateImage(vg, "image/btn_blue_20260518181012.png", 0)
    end
    if not imgBtnGreen then
        imgBtnGreen = nvgCreateImage(vg, "image/btn_green_20260518181154.png", 0)
    end

    -- 背景图片（Cover 模式铺满屏幕）
    if imgMenuBg ~= 0 then
        local imgW, imgH = 540, 960  -- 原图尺寸
        local scaleX, scaleY = w / imgW, h / imgH
        local scale = math_max(scaleX, scaleY)
        local drawW, drawH = imgW * scale, imgH * scale
        local ox, oy = (w - drawW) / 2, (h - drawH) / 2
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillPaint(vg, nvgImagePattern(vg, ox, oy, drawW, drawH, 0, imgMenuBg, 1.0))
        nvgFill(vg)
    else
        -- fallback: 纯色背景
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBA(10, 15, 35, 255))
        nvgFill(vg)
    end

    -- 标题和副标题已包含在背景图中，不再绘制文字
    nvgFontFaceId(vg, fontNormal)

    -- 双按钮：继续游戏 + 新游戏
    local isLoading = gameState.loading
    local hasSave = gameState.hasSave
    local btnW = S(160)
    local btnH = S(48)
    local btnGap = S(16)
    local btnX = (w - btnW) / 2
    local totalH = btnH * 4 + btnGap * 3
    local startY = h * 0.50 - totalH / 2
    local pulse = 0.85 + 0.15 * math.sin(time * 3)

    -- ---- 新游戏按钮（上方） ----
    local newY = startY
    local newEnabled = not isLoading

    -- 图片按钮边框
    if imgBtnBlue ~= 0 then
        local alpha = newEnabled and 1.0 or 0.4
        nvgBeginPath(vg)
        nvgRect(vg, btnX, newY, btnW, btnH)
        nvgFillPaint(vg, nvgImagePattern(vg, btnX, newY, btnW, btnH, 0, imgBtnBlue, alpha))
        nvgFill(vg)
    end

    nvgFontSize(vg, S(20))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if newEnabled then
        nvgFillColor(vg, nvgRGBA(200, 210, 240, 230))
    else
        nvgFillColor(vg, nvgRGBA(100, 110, 140, 150))
    end
    nvgText(vg, w / 2, newY + btnH / 2, "新游戏", nil)

    -- ---- 继续游戏按钮（下方） ----
    local contY = startY + btnH + btnGap
    local contEnabled = hasSave and not isLoading

    -- 图片按钮边框（继续游戏用蓝色大按钮）
    if imgBtnBlue ~= 0 then
        local alpha = contEnabled and 1.0 or 0.4
        -- 脉冲发光底层
        if contEnabled then
            nvgBeginPath(vg)
            nvgRect(vg, btnX - S(4), contY - S(4), btnW + S(8), btnH + S(8))
            nvgFillPaint(vg, nvgImagePattern(vg, btnX - S(4), contY - S(4), btnW + S(8), btnH + S(8), 0, imgBtnBlue, 0.3 * pulse))
            nvgFill(vg)
        end
        nvgBeginPath(vg)
        nvgRect(vg, btnX, contY, btnW, btnH)
        nvgFillPaint(vg, nvgImagePattern(vg, btnX, contY, btnW, btnH, 0, imgBtnBlue, alpha))
        nvgFill(vg)
    end

    nvgFontSize(vg, S(22))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if isLoading then
        local dots = string.rep(".", math.floor(time * 2) % 4)
        nvgFillColor(vg, nvgRGBA(160, 170, 200, 200))
        nvgText(vg, w / 2, contY + btnH / 2, "加载中" .. dots, nil)
    elseif contEnabled then
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, w / 2, contY + btnH / 2, "继续游戏", nil)
    else
        nvgFillColor(vg, nvgRGBA(100, 110, 140, 150))
        nvgText(vg, w / 2, contY + btnH / 2, "继续游戏", nil)
    end

    -- 存储按钮区域供点击检测
    M.menuNewGameRect = { x = btnX, y = newY, w = btnW, h = btnH }
    M.menuContinueRect = { x = btnX, y = contY, w = btnW, h = btnH }

    -- ---- 符文按钮（第三个） ----
    local runeY = startY + (btnH + btnGap) * 2
    local essenceCount = gameState.runeEssence or 0

    -- 图片按钮边框（紫色）
    if imgBtnPurple ~= 0 then
        nvgBeginPath(vg)
        nvgRect(vg, btnX, runeY, btnW, btnH)
        nvgFillPaint(vg, nvgImagePattern(vg, btnX, runeY, btnW, btnH, 0, imgBtnPurple, 1.0))
        nvgFill(vg)
    end

    nvgFontSize(vg, S(20))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 160, 255, 255))
    if essenceCount > 0 then
        -- 画 "符文" 偏左，然后画图标+数字偏右
        local midX = w / 2
        local midY = runeY + btnH / 2
        local countStr = tostring(essenceCount)
        local gap = S(6)
        local icoSz = S(16)
        -- 测量文字宽度
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        local labelW = nvgTextBounds(vg, 0, 0, "符文", nil)
        local countW = nvgTextBounds(vg, 0, 0, countStr, nil)
        local totalW = labelW + gap + icoSz + S(2) + countW
        local startX = midX - totalW / 2
        nvgText(vg, startX, midY, "符文", nil)
        -- 小图标
        local essenceImg = GetRuneIcon(vg, "image/rune_essence_20260409140302.png")
        local icoX = startX + labelW + gap
        local icoY = midY - icoSz / 2
        nvgBeginPath(vg)
        nvgRect(vg, icoX, icoY, icoSz, icoSz)
        nvgFillPaint(vg, nvgImagePattern(vg, icoX, icoY, icoSz, icoSz, 0, essenceImg, 1.0))
        nvgFill(vg)
        -- 数字
        nvgFillColor(vg, nvgRGBA(200, 160, 255, 255))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(vg, icoX + icoSz + S(2), midY, countStr, nil)
    else
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, w / 2, runeY + btnH / 2, "符文", nil)
    end

    M.menuRuneRect = { x = btnX, y = runeY, w = btnW, h = btnH }

    -- ---- 放置模式按钮（第四个） ----
    local idleY = startY + (btnH + btnGap) * 3

    -- 图片按钮边框（绿色）
    if imgBtnGreen ~= 0 then
        nvgBeginPath(vg)
        nvgRect(vg, btnX, idleY, btnW, btnH)
        nvgFillPaint(vg, nvgImagePattern(vg, btnX, idleY, btnW, btnH, 0, imgBtnGreen, 1.0))
        nvgFill(vg)
    end

    nvgFontSize(vg, S(20))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(120, 255, 180, 255))
    nvgText(vg, w / 2, idleY + btnH / 2, "放置模式", nil)

    M.menuIdleRect = { x = btnX, y = idleY, w = btnW, h = btnH }

    -- 底部提示已移除

    -- ==== 新游戏确认弹窗 ====
    if gameState.showNewGameConfirm then
        -- 半透明遮罩
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, w, h)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
        nvgFill(vg)

        -- 弹窗卡片
        local dlgW = S(220)
        local dlgH = S(140)
        local dlgX = (w - dlgW) / 2
        local dlgY = (h - dlgH) / 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, S(14))
        nvgFillColor(vg, nvgRGBA(30, 35, 55, 245))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, S(14))
        nvgStrokeColor(vg, nvgRGBA(80, 110, 180, 200))
        nvgStrokeWidth(vg, S(2))
        nvgStroke(vg)

        -- 提示文字
        nvgFontSize(vg, S(18))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
        nvgText(vg, w / 2, dlgY + S(30), "确认新游戏？", nil)

        nvgFontSize(vg, S(13))
        nvgFillColor(vg, nvgRGBA(180, 190, 220, 220))
        nvgText(vg, w / 2, dlgY + S(55), "当前存档将被覆盖", nil)

        -- 两个小按钮：取消 / 确认
        local dbW = S(80)
        local dbH = S(36)
        local dbY = dlgY + dlgH - dbH - S(18)
        local dbGap = S(20)
        local cancelX = w / 2 - dbW - dbGap / 2
        local confirmX = w / 2 + dbGap / 2

        -- 取消按钮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cancelX, dbY, dbW, dbH, S(8))
        nvgFillColor(vg, nvgRGBA(60, 65, 85, 230))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cancelX, dbY, dbW, dbH, S(8))
        nvgStrokeColor(vg, nvgRGBA(100, 110, 150, 180))
        nvgStrokeWidth(vg, S(1.5))
        nvgStroke(vg)
        nvgFontSize(vg, S(16))
        nvgFillColor(vg, nvgRGBA(180, 190, 220, 230))
        nvgText(vg, cancelX + dbW / 2, dbY + dbH / 2, "取消", nil)

        -- 确认按钮
        nvgBeginPath(vg)
        nvgRoundedRect(vg, confirmX, dbY, dbW, dbH, S(8))
        nvgFillPaint(vg, nvgLinearGradient(vg, confirmX, dbY, confirmX, dbY + dbH,
            nvgRGBA(200, 60, 60, 240),
            nvgRGBA(160, 40, 40, 240)))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, confirmX, dbY, dbW, dbH, S(8))
        nvgStrokeColor(vg, nvgRGBA(255, 100, 100, 180))
        nvgStrokeWidth(vg, S(1.5))
        nvgStroke(vg)
        nvgFontSize(vg, S(16))
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, confirmX + dbW / 2, dbY + dbH / 2, "确认", nil)

        -- 存储弹窗按钮区域
        M.dlgCancelRect = { x = cancelX, y = dbY, w = dbW, h = dbH }
        M.dlgConfirmRect = { x = confirmX, y = dbY, w = dbW, h = dbH }
    end
end

-- ============================================================================
-- 符文界面
-- ============================================================================


function M.DrawRuneScreen(vg, w, h)
    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, w, h)
    nvgFillPaint(vg, nvgLinearGradient(vg, 0, 0, 0, h,
        nvgRGBA(15, 10, 35, 255), nvgRGBA(8, 5, 25, 255)))
    nvgFill(vg)

    local essenceIcon = GetRuneIcon(vg, "image/rune_essence_20260409140302.png")
    nvgFontFace(vg, "sans")

    -- 标题
    nvgFontSize(vg, S(22))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(vg, nvgRGBA(200, 160, 255, 255))
    nvgText(vg, w / 2 + S(14), S(14), "符文系统", nil)
    local titleIconSz = S(22)
    nvgBeginPath(vg)
    nvgRect(vg, w / 2 - S(58), S(14), titleIconSz, titleIconSz)
    nvgFillPaint(vg, nvgImagePattern(vg, w / 2 - S(58), S(14), titleIconSz, titleIconSz, 0, essenceIcon, 1.0))
    nvgFill(vg)

    -- 精粹余额
    local essenceCount = gameState.runeEssence or 0
    nvgFontSize(vg, S(13))
    nvgFillColor(vg, nvgRGBA(180, 140, 255, 220))
    nvgText(vg, w / 2, S(40), string.format("精粹: %d", essenceCount), nil)

    -- 返回按钮（左上角）
    local backW = S(60)
    local backH = S(28)
    local backX = S(10)
    local backY = S(12)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, backX, backY, backW, backH, S(7))
    nvgFillColor(vg, nvgRGBA(50, 45, 70, 220))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, backX, backY, backW, backH, S(7))
    nvgStrokeColor(vg, nvgRGBA(120, 100, 180, 160))
    nvgStrokeWidth(vg, S(1))
    nvgStroke(vg)
    nvgFontSize(vg, S(13))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 190, 230, 230))
    nvgText(vg, backX + backW / 2, backY + backH / 2, "< 返回", nil)
    M.runeBackRect = { x = backX, y = backY, w = backW, h = backH }

    -- ============ 全部符文卡片（可滚动） ============
    local runes = Runes.RUNE_DEFS
    local runeCount = #runes

    local cardW = math_min(S(280), w - S(24))
    local cardH = S(72)
    local cardGap = S(10)
    local cardX = (w - cardW) / 2
    local listStartY = S(60)  -- 标题+余额下方
    local iconSz = S(26)

    -- 可滚动区域
    local listTop = listStartY
    local listBottom = h - S(28)  -- 底部提示预留
    local listHeight = listBottom - listTop
    local contentHeight = runeCount * (cardH + cardGap) - cardGap

    -- 限制滚动范围
    local maxScroll = math_max(0, contentHeight - listHeight)
    Runes.scrollY = math_max(0, math_min(maxScroll, Runes.scrollY))
    local scrollY = Runes.scrollY

    -- 裁剪区域
    nvgSave(vg)
    nvgScissor(vg, 0, listTop, w, listHeight)

    -- 清除旧的升级按钮区域
    M.runeUpgradeCount = runeCount
    for ci = 1, 10 do
        M["runeUpgradeRect_" .. ci] = nil
    end

    for i, rune in ipairs(runes) do
        local cy = listTop + (i - 1) * (cardH + cardGap) - scrollY

        -- 跳过不可见的卡片
        if cy + cardH < listTop then goto continue end
        if cy > listBottom then goto continue end

        local level = Runes.GetRuneLevel(rune.id)
        local value = Runes.GetRuneValue(rune.id)
        local cost = Runes.GetUpgradeCost(rune.id)
        local canAfford = essenceCount >= cost
        local rc = rune.color

        -- 卡片背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cy, cardW, cardH, S(8))
        nvgFillColor(vg, nvgRGBA(25, 20, 45, 230))
        nvgFill(vg)

        -- 卡片边框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, cardX, cy, cardW, cardH, S(8))
        nvgStrokeColor(vg, nvgRGBA(rc[1], rc[2], rc[3], canAfford and 180 or 80))
        nvgStrokeWidth(vg, S(1.5))
        nvgStroke(vg)

        -- 图标
        local iconX = cardX + S(8)
        local iconY = cy + (cardH - iconSz) / 2
        local runeImg = GetRuneIcon(vg, rune.icon)
        nvgBeginPath(vg)
        nvgRect(vg, iconX, iconY, iconSz, iconSz)
        nvgFillPaint(vg, nvgImagePattern(vg, iconX, iconY, iconSz, iconSz, 0, runeImg, 1.0))
        nvgFill(vg)

        -- 名称 + 等级
        local nameX = cardX + S(40)
        nvgFontSize(vg, S(14))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(rc[1], rc[2], rc[3], 255))
        nvgText(vg, nameX, cy + S(20), rune.name .. "  Lv." .. level, nil)

        -- 描述
        local desc = rune.descFunc(level, value)
        nvgFontSize(vg, S(10))
        nvgFillColor(vg, nvgRGBA(170, 170, 200, 200))
        nvgText(vg, nameX, cy + S(40), desc, nil)

        -- 升级按钮
        local ubW = S(66)
        local ubH = S(28)
        local ubX = cardX + cardW - ubW - S(8)
        local ubY = cy + (cardH - ubH) / 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, ubX, ubY, ubW, ubH, S(6))
        if canAfford then
            nvgFillPaint(vg, nvgLinearGradient(vg, ubX, ubY, ubX, ubY + ubH,
                nvgRGBA(rc[1], rc[2], rc[3], 200),
                nvgRGBA(math_floor(rc[1] * 0.6), math_floor(rc[2] * 0.6), math_floor(rc[3] * 0.6), 200)))
        else
            nvgFillColor(vg, nvgRGBA(40, 35, 60, 200))
        end
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, ubX, ubY, ubW, ubH, S(6))
        nvgStrokeColor(vg, canAfford and nvgRGBA(255, 255, 255, 80) or nvgRGBA(80, 70, 110, 120))
        nvgStrokeWidth(vg, S(1))
        nvgStroke(vg)

        -- 费用（图标+数字）
        local costStr = tostring(cost)
        local costIconSz = S(12)
        nvgFontSize(vg, S(11))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, canAfford and nvgRGBA(255, 255, 255, 255) or nvgRGBA(120, 110, 150, 160))
        local costTextX = ubX + ubW / 2 + S(7)
        nvgText(vg, costTextX, ubY + ubH / 2, costStr, nil)
        nvgBeginPath(vg)
        local costIconX = costTextX - S(7) - costIconSz
        local costIconY = ubY + (ubH - costIconSz) / 2
        nvgRect(vg, costIconX, costIconY, costIconSz, costIconSz)
        nvgFillPaint(vg, nvgImagePattern(vg, costIconX, costIconY, costIconSz, costIconSz, 0, essenceIcon, canAfford and 1.0 or 0.5))
        nvgFill(vg)

        M["runeUpgradeRect_" .. i] = { x = ubX, y = ubY, w = ubW, h = ubH }

        ::continue::
    end

    nvgRestore(vg)  -- 恢复裁剪

    -- 滚动条指示器（内容超出时显示）
    if maxScroll > 0 then
        local scrollBarH = math_max(S(20), listHeight * (listHeight / contentHeight))
        local scrollBarY = listTop + (listHeight - scrollBarH) * (scrollY / maxScroll)
        local scrollBarX = w - S(6)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, scrollBarX, scrollBarY, S(3), scrollBarH, S(1.5))
        nvgFillColor(vg, nvgRGBA(160, 140, 200, 100))
        nvgFill(vg)
    end

    -- 底部提示
    nvgFontSize(vg, S(10))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(120, 110, 160, 140))
    nvgText(vg, w / 2, h - S(12), "闯关失败时根据到达轮次获得符文精粹", nil)
end

return M
