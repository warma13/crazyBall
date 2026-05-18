-- ============================================================================
-- Physics.lua - 纯物理模拟、钢珠投放、音效
-- 所有效果逻辑已委托给管线模块：
--   PegEffects  → 撞钉效果
--   BallEffects → 球属性 & 每帧物理修改
--   Settlement  → 落袋结算
-- ============================================================================

local Config = require("Config")
local State = require("State")
local BigNum = require("BigNum")
local Upgrades = require("Upgrades")
local PegEffects = require("PegEffects")
local BallEffects = require("BallEffects")
local Settlement = require("Settlement")
local Enchantment = require("Enchantment")

-- 使用原始 math 函数绕过 BigNum 猴子补丁（Physics 内部不使用 BigNum，无需类型检查）
local _rawFloor = BigNum._rawFloor
local _rawMax = BigNum._rawMax
local _rawMin = BigNum._rawMin

local CONFIG = Config.CONFIG
local gameState = State.gameState

local M = {}

-- ============================================================================
-- 空间网格（加速碰撞检测）
-- ============================================================================
local grid = {}          -- grid[cellKey] = { peg1, peg2, ... }
local gridCellSize = 0   -- 每格大小
local gridCols = 0
local gridRows = 0
local gridOffsetX = 0
local gridOffsetY = 0

--- 根据坐标获取网格 key
local function gridKey(col, row)
    return row * 1000 + col
end

--- 重建空间网格（钉子变化时调用）
function M.RebuildGrid()
    grid = {}
    if #gameState.pegs == 0 then return end

    -- 碰撞半径决定格子大小（2倍碰撞距离保证邻居覆盖）
    local pegR = CONFIG.PEG_RADIUS * (gameState.boardScale or 1)
    local maxBallR = CONFIG.BALL_RADIUS * (gameState.boardScale or 1) * 2  -- 巨型弹珠
    local cellSize = (pegR + maxBallR) * 2.5
    if cellSize < 10 then cellSize = 10 end
    gridCellSize = cellSize

    gridOffsetX = gameState.boardLeft
    gridOffsetY = gameState.boardTop
    local boardW = gameState.boardRight - gameState.boardLeft
    local boardH = gameState.boardBottom - gameState.boardTop
    gridCols = math.ceil(boardW / cellSize) + 1
    gridRows = math.ceil(boardH / cellSize) + 1

    for _, peg in ipairs(gameState.pegs) do
        local col = _rawFloor((peg.x - gridOffsetX) / cellSize)
        local row = _rawFloor((peg.y - gridOffsetY) / cellSize)
        local key = gridKey(col, row)
        if not grid[key] then grid[key] = {} end
        table.insert(grid[key], peg)
    end
end

--- 查询球附近的钉子（只查所在格和相邻8格）
function M.QueryNearbyPegs(bx, by)
    local col = _rawFloor((bx - gridOffsetX) / gridCellSize)
    local row = _rawFloor((by - gridOffsetY) / gridCellSize)
    -- 复用静态表避免每帧分配
    local result = M._nearbyResult
    local n = 0
    for dr = -1, 1 do
        for dc = -1, 1 do
            local cell = grid[gridKey(col + dc, row + dr)]
            if cell then
                for _, peg in ipairs(cell) do
                    n = n + 1
                    result[n] = peg
                end
            end
        end
    end
    -- 清理尾部旧数据
    for i = n + 1, #result do result[i] = nil end
    return result, n
end
M._nearbyResult = {}  -- 预分配复用表
M._gravSources = {}   -- 引力之井源球复用表

--- 播放音效（受设置中 sfxVolume 调节）
function M.PlaySfx(sound, gain)
    if not sound or not State.sfxScene_ then return end
    local vol = gameState.settings.sfxVolume
    if vol <= 0 then return end
    local node = State.sfxScene_:CreateChild("SFX")
    local source = node:CreateComponent("SoundSource")
    source.soundType = "Effect"
    source.gain = (gain or 0.5) * vol
    source.autoRemoveMode = REMOVE_NODE
    source:Play(sound)
end

--- 重新计算布局
function M.RecalcLayout()
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local w = physW / dpr
    local h = physH / dpr

    -- 棋盘元素缩放系数（基于参考宽度 320，与 UI 缩放一致）
    local bs = w / 320
    gameState.boardScale = bs

    local splitY = _rawFloor(h * CONFIG.BOARD_SPLIT_RATIO)

    gameState.boardLeft = CONFIG.BOARD_PADDING_X
    gameState.boardRight = w - CONFIG.BOARD_PADDING_X
    gameState.boardTop = CONFIG.BOARD_MARGIN_TOP * bs + 30 * bs
    gameState.boardBottom = splitY
    gameState.splitY = splitY
    gameState.panelHeight = h - splitY
    gameState.screenW = w
    gameState.screenH = h

    -- 内容区域：board 向内缩进，撞钉和口袋在此范围内
    local cmx = CONFIG.CONTENT_MARGIN_X * bs
    local cmt = CONFIG.CONTENT_MARGIN_TOP * bs
    local cmb = CONFIG.CONTENT_MARGIN_BOT * bs
    gameState.contentLeft   = gameState.boardLeft + cmx
    gameState.contentRight  = gameState.boardRight - cmx
    gameState.contentTop    = gameState.boardTop + cmt
    gameState.contentBottom = gameState.boardBottom - cmb

    -- 口袋边界和中心（按图片分隔线比例计算）
    local bL = gameState.boardLeft
    local bW = gameState.boardRight - bL
    local dividers = CONFIG.SLOT_DIVIDERS
    local innerL = CONFIG.SLOT_INNER_LEFT
    local innerR = CONFIG.SLOT_INNER_RIGHT
    -- 边界数组: [innerLeft, div1, div2, ..., divN, innerRight]
    local edges = { bL + innerL * bW }
    for _, d in ipairs(dividers) do
        edges[#edges + 1] = bL + d * bW
    end
    edges[#edges + 1] = bL + innerR * bW
    gameState.slotEdges = edges
    -- 中心和宽度数组
    local centers = {}
    local widths = {}
    local slotCount = #gameState.slots
    for i = 1, slotCount do
        local l = edges[i] or edges[1]
        local r = edges[i + 1] or edges[#edges]
        centers[i] = (l + r) / 2
        widths[i] = r - l
    end
    gameState.slotCenters = centers
    gameState.slotWidths = widths
    gameState.slotWidth = bW / slotCount  -- 仍保留均分宽度用于落球检测
end

--- 初始化钉子
function M.InitPegs()
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    local w = physW / dpr
    local h = physH / dpr

    local splitY = _rawFloor(h * CONFIG.BOARD_SPLIT_RATIO)

    local bs = w / 320
    gameState.boardScale = bs

    gameState.boardLeft = CONFIG.BOARD_PADDING_X
    gameState.boardRight = w - CONFIG.BOARD_PADDING_X
    gameState.boardTop = CONFIG.BOARD_MARGIN_TOP * bs + 30 * bs
    gameState.boardBottom = splitY

    -- 内容区域
    local cmx = CONFIG.CONTENT_MARGIN_X * bs
    local cmt = CONFIG.CONTENT_MARGIN_TOP * bs
    local cmb = CONFIG.CONTENT_MARGIN_BOT * bs
    gameState.contentLeft   = gameState.boardLeft + cmx
    gameState.contentRight  = gameState.boardRight - cmx
    gameState.contentTop    = gameState.boardTop + cmt
    gameState.contentBottom = gameState.boardBottom - cmb

    local slotCount = #gameState.slots
    local contentW = gameState.contentRight - gameState.contentLeft
    local contentH = gameState.contentBottom - gameState.contentTop - CONFIG.SLOT_HEIGHT * bs

    -- 口袋边界和中心（按图片分隔线比例计算）
    local bL = gameState.boardLeft
    local bW = gameState.boardRight - bL
    local dividers = CONFIG.SLOT_DIVIDERS
    local innerL = CONFIG.SLOT_INNER_LEFT
    local innerR = CONFIG.SLOT_INNER_RIGHT
    local edges = { bL + innerL * bW }
    for _, d in ipairs(dividers) do
        edges[#edges + 1] = bL + d * bW
    end
    edges[#edges + 1] = bL + innerR * bW
    gameState.slotEdges = edges
    local centers = {}
    local widths = {}
    for i = 1, slotCount do
        local l = edges[i] or edges[1]
        local r = edges[i + 1] or edges[#edges]
        centers[i] = (l + r) / 2
        widths[i] = r - l
    end
    gameState.slotCenters = centers
    gameState.slotWidths = widths
    gameState.slotWidth = bW / slotCount

    gameState.pegs = {}
    local rowSpacing = contentH / (CONFIG.PEG_ROWS + 1)

    for row = 1, CONFIG.PEG_ROWS do
        local y = gameState.contentTop + row * rowSpacing
        local isOddRow = (row % 2 == 1)
        local pegsInRow = isOddRow and _rawMax(slotCount - 1, 2) or _rawMax(slotCount, 3)

        for col = 1, pegsInRow do
            local x
            if isOddRow then
                x = gameState.contentLeft + col * (contentW / (pegsInRow + 1))
            else
                x = gameState.contentLeft + (col - 0.5) * (contentW / pegsInRow)
            end
            table.insert(gameState.pegs, {
                x = x, y = y,
                hitTimer = 0,
            })
        end
    end

    M.RebuildGrid()

    -- 注入空间网格查询到 PegEffects 和 Settlement（避免循环 require）
    local gridQueryFn = function(x, y)
        return M.QueryNearbyPegs(x, y)
    end
    PegEffects.SetGridQuery(gridQueryFn)
    Settlement.SetGridQuery(gridQueryFn)
end

--- 投放单个钢珠
function M.DropBall(dropX)
    if #gameState.balls >= CONFIG.MAX_BALLS then return false end

    local ballType = Config.BALL_TYPES[gameState.selectedBallType]
    local level = gameState.ballLevels[gameState.selectedBallType]

    -- 超频投射：提升投球等级
    local boostLv = Upgrades.GetEffectLevel("drop_level_boost")
    if boostLv > 0 then
        level = level + _rawFloor(Upgrades.GetEffectValue("drop_level_boost"))
    end

    -- 球价值通过 BallEffects 管线计算（含增值效果）
    local value = BallEffects.GetBallValue(gameState.selectedBallType, level)

    if gameState.coins < value then return false end
    gameState.coins = gameState.coins - value

    -- 球半径通过 BallEffects 管线计算（含巨型弹珠效果）
    local ballRadius = BallEffects.GetBallRadius()

    table.insert(gameState.balls, {
        x = dropX,
        y = gameState.contentTop - 5,
        vx = (math.random() - 0.5) * 20 * (gameState.boardScale or 1),
        vy = 0,
        radius = ballRadius,
        typeIndex = gameState.selectedBallType,
        value = value,
        trail = {},
        alive = true,
        pegHits = 0,
        hasSplit = false,
        aliveTime = 0,
        baseRadius = ballRadius,
    })
    M.PlaySfx(State.sfxBallDrop, 0.3)
    return true
end

--- 天降弹珠（免费铁球）
function M.DropSkyBall()
    if #gameState.balls >= CONFIG.MAX_BALLS then return end

    local level = _rawMax(1, gameState.ballLevels[1])
    local value = BallEffects.GetBallValue(1, level)

    local dropX = gameState.contentLeft + math.random() * (gameState.contentRight - gameState.contentLeft)

    local bs = gameState.boardScale or 1
    table.insert(gameState.balls, {
        x = dropX,
        y = gameState.contentTop - 5,
        vx = (math.random() - 0.5) * 20 * bs,
        vy = 0,
        radius = CONFIG.BALL_RADIUS * bs,
        typeIndex = 1,
        value = value,
        trail = {},
        alive = true,
        pegHits = 0,
        aliveTime = 0,
        baseRadius = CONFIG.BALL_RADIUS * bs,
    })
end

--- 多球投放
function M.DropMultipleBalls(randomPos)
    -- 基础1颗 + 多球投放效果 + 额外弹珠效果
    local multiCount = 1
    local multiLv = Upgrades.GetEffectLevel("multi_drop")
    if multiLv > 0 then
        multiCount = multiCount + _rawFloor(Upgrades.GetEffectValue("multi_drop"))
    end
    local extraBall = Upgrades.GetEffectValue("extra_ball")
    if extraBall > 0 then
        multiCount = multiCount + _rawFloor(extraBall)
    end
    -- 附魔：额外球概率（extra_ball, 加算，每级+5%）
    local enchantExtra = Enchantment.GetValue(gameState.selectedBallType, "extra_ball")
    if enchantExtra > 0 and math.random() < enchantExtra then
        multiCount = multiCount + 1
    end

    local boardCenterX = (gameState.contentLeft + gameState.contentRight) / 2
    local spread = (gameState.contentRight - gameState.contentLeft) * 0.3

    local dropped = 0
    for i = 1, multiCount do
        local dropX
        if randomPos then
            dropX = gameState.contentLeft + 20 + math.random() * (gameState.contentRight - gameState.contentLeft - 40)
        else
            local offset = 0
            if multiCount > 1 then
                offset = ((i - 1) / (multiCount - 1) - 0.5) * spread
            end
            dropX = boardCenterX + offset + (math.random() - 0.5) * 20
        end
        local ok = M.DropBall(dropX)
        if not ok then break end
        dropped = dropped + 1
    end
    return dropped
end

--- 更新钢珠物理
function M.UpdateBalls(dt)
    local pegR = PegEffects.GetPegCollisionRadius()
    local bs = gameState.boardScale or 1
    local nudge = CONFIG.RANDOM_NUDGE * bs
    local bottomY = gameState.contentBottom - 5
    local boardLeft = gameState.contentLeft
    local boardRight = gameState.contentRight
    local boardBottom = gameState.contentBottom
    local pegHitDuration = CONFIG.PEG_HIT_DURATION
    local maxBalls = CONFIG.MAX_BALLS
    local ballRadius = CONFIG.BALL_RADIUS
    local dividerHeight = CONFIG.DIVIDER_HEIGHT
    local dividerWidth = CONFIG.DIVIDER_WIDTH
    local slotWidth = gameState.slotWidth
    local slots = gameState.slots
    local slotCount = #slots
    local balls = gameState.balls
    local pegs = gameState.pegs

    -- 预缓存常用效果值（避免每球每帧调用）
    local gravWellVal = Upgrades.GetEffectValue("gravity_well")
    local math_sqrt = math.sqrt
    local math_random = math.random
    local math_abs = math.abs
    local math_floor = _rawFloor
    local math_max = _rawMax
    local math_min = _rawMin
    -- BigNum 兼容版本（用于 ball.value/addedValue 等 BigNum 操作）
    local bn_floor = math.floor
    local bn_max = math.max

    local i = 1
    while i <= #balls do
        local ball = balls[i]

        if ball.alive then
            -- 获取球类型的特殊效果（仅用于分裂判定）
            local ballType = Config.BALL_TYPES[ball.typeIndex]
            local eff = ballType and ballType.effect
            local ballR = ball.radius
            local collisionDist = pegR + ballR
            local leftWall = boardLeft + ballR
            local rightWall = boardRight - ballR

            -- 追踪球存活时间（琥珀球节律效果需要）
            ball.aliveTime = (ball.aliveTime or 0) + dt

            -- 重力和衰减通过 BallEffects 管线获取
            local gravity = BallEffects.GetGravity(ball)
            local damping = BallEffects.GetDamping(ball)

            ball.vy = ball.vy + gravity * dt
            ball.x = ball.x + ball.vx * dt
            ball.y = ball.y + ball.vy * dt

            -- 拖尾：环形缓冲（避免 table.insert(1) 的 O(n) 搬移）
            local trailIdx = (ball.trailHead or 0) % 6 + 1
            if not ball.trail[trailIdx] then
                ball.trail[trailIdx] = { x = ball.x, y = ball.y }
            else
                ball.trail[trailIdx].x = ball.x
                ball.trail[trailIdx].y = ball.y
            end
            ball.trailHead = trailIdx
            if (ball.trailLen or 0) < 6 then
                ball.trailLen = (ball.trailLen or 0) + 1
            end

            -- 钉子碰撞（空间网格加速）
            local nearbyPegs = M.QueryNearbyPegs(ball.x, ball.y)
            for _, peg in ipairs(nearbyPegs) do
                local dx = ball.x - peg.x
                local dy = ball.y - peg.y
                local distSq = dx * dx + dy * dy
                if distSq < collisionDist * collisionDist and distSq > 0.01 then
                    local dist = math_sqrt(distSq)
                    local nx = dx / dist
                    local ny = dy / dist

                    -- 分离：多推 1px 防止下帧重叠
                    local overlap = collisionDist - dist + 1.0
                    ball.x = ball.x + nx * overlap
                    ball.y = ball.y + ny * overlap

                    local dot = ball.vx * nx + ball.vy * ny
                    local pegDamping = (eff and eff.keepSpeed) and 1.0 or damping
                    ball.vx = (ball.vx - 2 * dot * nx) * pegDamping
                    ball.vy = (ball.vy - 2 * dot * ny) * pegDamping

                    -- 防粘滞：确保弹开速度不低于最小阈值
                    local outSpeed = ball.vx * nx + ball.vy * ny
                    local minBounceSpeed = 60
                    if outSpeed < minBounceSpeed then
                        local boost = minBounceSpeed - outSpeed
                        ball.vx = ball.vx + nx * boost
                        ball.vy = ball.vy + ny * boost
                    end

                    ball.vx = ball.vx + (math_random() - 0.5) * nudge

                    peg.hitTimer = pegHitDuration
                    if not gameState.pegSfxPlayed then
                        M.PlaySfx(State.sfxPegHit, 0.15)
                        gameState.pegSfxPlayed = true
                    end

                    -- 弹钉效果管线（所有撞钉效果集中处理）
                    PegEffects.OnPegHit(ball, peg, gameState.pegs, gameState.balls, false)

                    -- 附魔：撞钉概率分裂（peg_split, 乘算，每级5%）
                    local enchantSplitChance = Enchantment.GetValue(ball.typeIndex, "peg_split")
                    if enchantSplitChance > 0 and #balls < maxBalls
                        and math.random() < enchantSplitChance then
                        table.insert(balls, {
                            x = ball.x,
                            y = ball.y,
                            vx = -ball.vx + (math.random() - 0.5) * 30 * bs,
                            vy = ball.vy * 0.5,
                            radius = ballRadius * bs,
                            typeIndex = ball.typeIndex,
                            value = ball.value,
                            trail = {},
                            alive = true,
                            pegHits = 0,
                            hasSplit = true,
                            splitCount = 999,
                            aliveTime = 0,
                            baseRadius = ballRadius * bs,
                        })
                    end

                    -- 分裂效果（银球特有，保留在 Physics 中因为涉及生成新球）
                    if eff and eff.id == "split" then
                        local threshold = eff.hitThreshold
                        local sbLv = Upgrades.GetEffectLevel("silver_boost")
                        if sbLv > 0 then
                            local reduce = math_min(sbLv, 3)
                            threshold = math_max(1, threshold - reduce)
                        end

                        local canSplitAgain = (sbLv >= 3)
                        local maxSplitCount = 1 + math_floor(sbLv / 3)
                        local splitCount = ball.splitCount or 0
                        local splitBalls = 1 + math_floor(sbLv / 5)

                        if (splitCount < maxSplitCount)
                            and (ball.pegHits or 0) >= threshold
                            and #balls < maxBalls then
                            ball.splitCount = splitCount + 1
                            if canSplitAgain then
                                ball.pegHits = 0
                            else
                                ball.hasSplit = true
                            end

                            -- 分裂传承：继承母球的弹钉增值
                            local inheritedValue = ball.value
                            local splitInheritVal = Upgrades.GetEffectValue("split_inherit")
                            if splitInheritVal > 0 and (ball.addedValue or 0) > 0 then
                                local inherited = bn_floor(ball.addedValue * splitInheritVal)
                                inheritedValue = ball.value - ball.addedValue + inherited
                                -- 确保不低于基础值
                                inheritedValue = bn_max(inheritedValue, ball.value - (ball.addedValue or 0))
                            end

                            -- 分裂新星：分裂时范围内钉产金（用空间网格加速）
                            local splitNovaVal = Upgrades.GetEffectValue("split_nova")
                            if splitNovaVal > 0 then
                                local novaPegs = M.QueryNearbyPegs(ball.x, ball.y)
                                for _, p in ipairs(novaPegs) do
                                    local dx2 = ball.x - p.x
                                    local dy2 = ball.y - p.y
                                    local d2 = math_sqrt(dx2 * dx2 + dy2 * dy2)
                                    if d2 <= ball.radius + 20 then
                                        local novaGold = bn_floor(ball.value * splitNovaVal)
                                        if novaGold > 0 then
                                            State.AddEarnings(novaGold)
                                        end
                                        p.hitTimer = pegHitDuration
                                    end
                                end
                            end

                            for sb = 1, splitBalls do
                                if #balls >= maxBalls then break end
                                local angleOffset = sb == 1 and 1 or -1
                                table.insert(balls, {
                                    x = ball.x,
                                    y = ball.y,
                                    vx = -ball.vx * angleOffset + (math_random() - 0.5) * 30 * bs,
                                    vy = ball.vy * 0.5,
                                    radius = ballRadius * bs,
                                    typeIndex = ball.typeIndex,
                                    value = inheritedValue,
                                    trail = {},
                                    alive = true,
                                    pegHits = 0,
                                    hasSplit = true,
                                    splitCount = ball.splitCount,
                                    aliveTime = 0,
                                    baseRadius = ballRadius * bs,
                                    addedValue = splitInheritVal > 0 and bn_floor((ball.addedValue or 0) * splitInheritVal) or 0,
                                })
                            end
                        end
                    end
                end
            end

            -- 墙壁
            if ball.x < leftWall then
                ball.x = leftWall
                ball.vx = math_abs(ball.vx) * damping
            elseif ball.x > rightWall then
                ball.x = rightWall
                ball.vx = -math_abs(ball.vx) * damping
            end

            -- 挡板碰撞
            local dividerTop = boardBottom - dividerHeight * bs
            local dividerBottom2 = boardBottom
            if ball.y + ballR > dividerTop and ball.y - ballR < dividerBottom2 then
                local divHalfW = dividerWidth * bs * 0.5
                for di = 0, slotCount do
                    local dx = boardLeft + di * slotWidth
                    local distX = ball.x - dx
                    if math_abs(distX) < ballR + divHalfW then
                        local clampY = math_max(dividerTop, math_min(ball.y, dividerBottom2))
                        if math_abs(ball.y - clampY) < ballR or (ball.y >= dividerTop and ball.y <= dividerBottom2) then
                            local pushDist = ballR + divHalfW
                            if distX > 0 then
                                ball.x = dx + pushDist
                            else
                                ball.x = dx - pushDist
                            end
                            ball.vx = -ball.vx * damping * 0.7
                        end
                    end
                end
            end

            -- 引力之井：延迟到所有球处理完后统一执行（见下方 _gravWell 块）
            -- 这里仅标记球已满足触发条件
            if gravWellVal > 0 and (ball.pegHits or 0) >= 5 then
                ball._gravSource = true
            end

            -- 幸运弹跳通过 BallEffects 管线处理
            BallEffects.ApplyLuckyBounce(ball, dt, bottomY)

            -- 落入坑位 → 结算管线
            if ball.y >= bottomY then
                ball.alive = false
                Settlement.OnBallLanded(ball)
                M.PlaySfx(State.sfxSlotLand, 0.4)
            end
        end

        if not ball.alive then
            -- 标记为待清理，稍后批量移除
            ball._dead = true
        end

        i = i + 1
    end

    -- 引力之井：单遍 O(n) 处理，替代之前 O(n²) 嵌套
    -- 思路：收集所有 gravSource 球 → 对每个其他球找最近 source → 引力偏向最近钉
    if gravWellVal > 0 then
        -- 收集源球（pegHits >= 5 的活球）
        local srcCount = 0
        local _gravSources = M._gravSources
        for si = 1, #balls do
            local b = balls[si]
            if b._gravSource then
                srcCount = srcCount + 1
                _gravSources[srcCount] = b
                b._gravSource = nil
            end
        end
        for si = srcCount + 1, #_gravSources do _gravSources[si] = nil end

        if srcCount > 0 then
            local wellSq = gravWellVal * gravWellVal
            for ti = 1, #balls do
                local target = balls[ti]
                if target.alive and not target._gravSource then
                    -- 找最近的 source 球
                    local bestDistSq = wellSq
                    local bestSrc = nil
                    for si = 1, srcCount do
                        local src = _gravSources[si]
                        if src ~= target then
                            local gdx = src.x - target.x
                            local gdy = src.y - target.y
                            local gd2 = gdx * gdx + gdy * gdy
                            if gd2 < bestDistSq then
                                bestDistSq = gd2
                                bestSrc = src
                            end
                        end
                    end
                    if bestSrc then
                        local gd = math_sqrt(bestDistSq)
                        -- 找目标球附近最近弹钉
                        local nearPeg, nearDist2 = nil, 1e18
                        local nearby = M.QueryNearbyPegs(target.x, target.y)
                        for _, p in ipairs(nearby) do
                            local pdx = target.x - p.x
                            local pdy = target.y - p.y
                            local pd2 = pdx * pdx + pdy * pdy
                            if pd2 < nearDist2 then
                                nearDist2 = pd2
                                nearPeg = p
                            end
                        end
                        if nearPeg then
                            local dirX = nearPeg.x - target.x
                            local dirY = nearPeg.y - target.y
                            local dirLen = math_sqrt(dirX * dirX + dirY * dirY)
                            if dirLen > 1 then
                                local force = 80 * (1 - gd / gravWellVal) * dt
                                target.vx = target.vx + (dirX / dirLen) * force
                                target.vy = target.vy + (dirY / dirLen) * force
                            end
                        end
                    end
                end
            end
        end
    end

    -- 批量移除死球（从后向前 swap-and-truncate，避免 O(n²)）
    local n = #gameState.balls
    local j = 1
    while j <= n do
        if gameState.balls[j]._dead then
            gameState.balls[j] = gameState.balls[n]
            gameState.balls[n] = nil
            n = n - 1
        else
            j = j + 1
        end
    end
end

--- 更新钉子动画
function M.UpdatePegs(dt)
    for _, peg in ipairs(gameState.pegs) do
        if peg.hitTimer > 0 then
            peg.hitTimer = peg.hitTimer - dt
        end
    end
end

--- 更新飘字（过期 popup 回收到对象池）
function M.UpdatePopups(dt)
    local popups = gameState.popups
    local n = #popups
    local j = 1
    while j <= n do
        local p = popups[j]
        p.timer = p.timer - dt
        p.elapsed = (p.elapsed or 0) + dt
        if p.timer <= 0 then
            popups[j] = popups[n]
            popups[n] = nil
            n = n - 1
            -- 回收到对象池
            Settlement.ReleasePopup(p)
        else
            j = j + 1
        end
    end
end

return M
