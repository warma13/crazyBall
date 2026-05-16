-- ============================================================================
-- 疯狂弹珠 - 入口文件
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local BigNum = require("BigNum")
local State = require("State")
local Slots = require("Slots")
local Physics = require("Physics")
local Upgrades = require("Upgrades")
local Renderer = require("Renderer")
local GameUI = require("GameUI")
local Leaderboard = require("Leaderboard")
local SaveSystem = require("SaveSystem")
local PegEffects = require("PegEffects")
local Settlement = require("Settlement")

local Runes = require("Runes")
local EventBus = require("EventBus")
local Profiler = require("Profiler")
local PlatformUtils = require("urhox-libs.Platform.PlatformUtils")

---@diagnostic disable-next-line: undefined-global
local sdk = sdk

local CONFIG = Config.CONFIG
local gameState = State.gameState

-- ============================================================================
-- 轮次系统
-- ============================================================================

--- 计算指定轮次的目标值（返回 BigNum）
local function CalcRoundTarget(roundNum)
    local ROUND = Config.ROUND
    local base = math.floor(BigNum.new(ROUND.BASE_TARGET) * BigNum.new(ROUND.GROWTH_RATE) ^ (roundNum - 1))
    local reduction = Runes.GetRuneValue("rune_tenacity")  -- 0~0.25
    if reduction > 0 then
        base = math.floor(base * (1 - reduction))
    end
    return base
end

--- 开始新一轮
local function StartRound(roundNum)
    gameState.round = roundNum
    gameState.roundTimeLeft = Config.ROUND.TIME_LIMIT + Runes.GetRuneValue("rune_time")
    gameState.roundEarned = BigNum.new(0)
    gameState.roundTarget = CalcRoundTarget(roundNum)
    gameState.roundPhase = "playing"

    -- 清空场上弹珠
    gameState.balls = {}
    gameState.popups = {}
    gameState.comboCount = 0
    gameState.comboTimer = 0

    -- 重置口袋大师流派的轮次状态
    gameState.slotCycleHistory = {}
    gameState.slotVisitedThisRound = {}
    gameState.slotJackpotReady = false
    gameState.slotHitCountThisRound = {}
    gameState.slotEchoBonuses = {}

    -- 重置补强流派的轮次状态
    gameState.fortuneStackBonus = 0
    gameState.fortuneShareTimer = 0
    gameState.fortuneShareRatio = 0
    gameState.critStreakCount = 0
    gameState.comboBurstCount = 0

    EventBus.emit("round_started", { round = roundNum })
    print(string.format("[Round] Start round %d, target=%s, time=%ds",
        roundNum, tostring(gameState.roundTarget), Config.ROUND.TIME_LIMIT))
end

--- 过关成功（无缝进入下一轮，不暂停、不清弹珠）
local function OnRoundSuccess()
    -- 飘字提示
    local S = State.S
    local cx = (gameState.boardLeft + gameState.boardRight) / 2
    local cy = (gameState.boardTop + gameState.boardBottom) / 2
    table.insert(gameState.popups, {
        x = cx, y = cy - S(20),
        text = "过关！",
        color = { 100, 255, 140, 255 },
        timer = 1.8, fontSize = 28,
    })

    -- 时间结晶：剩余秒 × value × 口袋平均倍率 → 额外金币
    local crystalVal = Upgrades.GetEffectValue("time_crystal")
    if crystalVal > 0 and gameState.roundTimeLeft > 0 then
        local totalSlotMult = 0
        local slotCount = #gameState.slots
        for _, s in ipairs(gameState.slots) do
            totalSlotMult = totalSlotMult + (s.level or 1)
        end
        local avgSlotMult = slotCount > 0 and (totalSlotMult / slotCount) or 1
        local crystalBonus = math.floor(gameState.roundTimeLeft * crystalVal * avgSlotMult)
        if crystalBonus > 0 then
            State.AddEarnings(crystalBonus)
            table.insert(gameState.popups, {
                x = cx, y = cy + S(65),
                text = "时间结晶 +" .. crystalBonus,
                color = { 150, 220, 255, 255 },
                timer = 1.5, fontSize = 14,
            })
            print(string.format("[TimeCrystal] remaining=%.1fs, val=%.3f, avgMult=%.1f, bonus=%s",
                gameState.roundTimeLeft, crystalVal, avgSlotMult, tostring(crystalBonus)))
        end
    end

    -- 过关奖励宝石（基础1 + 每5轮额外+1，中后期增长更慢）
    local gemReward = 1 + math.floor(gameState.round / 5)
    State.AddGems(gemReward)
    table.insert(gameState.popups, {
        x = cx, y = cy + S(40),
        text = "+" .. gemReward,
        icon = "gem",
        color = { 130, 200, 255, 255 },
        timer = 1.5, fontSize = 16,
    })

    Physics.PlaySfx(State.sfxRoundSuccess, 0.6)
    gameState.screenShake = 0.3

    print(string.format("[Round] Round %d SUCCESS! gems=%d", gameState.round, gemReward))

    -- 直接推进下一轮，保持 playing 状态，不清弹珠
    local nextRound = gameState.round + 1
    gameState.round = nextRound
    gameState.roundTimeLeft = Config.ROUND.TIME_LIMIT + Runes.GetRuneValue("rune_time")
    gameState.roundEarned = BigNum.new(0)
    gameState.roundTarget = CalcRoundTarget(nextRound)

    EventBus.emit("round_started", { round = nextRound })
    print(string.format("[Round] Seamless start round %d, target=%s", nextRound, tostring(gameState.roundTarget)))

    -- 过关时保存
    SaveSystem.Save()
end

--- 时间到失败 → 直接重置
--- @param adWatched boolean|nil 是否看了广告（双倍精粹+携带20%资源）
--- @param carryCoins any|nil BigNum 携带金币
--- @param carryGems number|nil 携带宝石
local function OnRoundFailed(adWatched, carryCoins, carryGems)
    local failedRound = gameState.round
    local earnedSnap = tostring(gameState.roundEarned)
    local targetSnap = tostring(gameState.roundTarget)

    Physics.PlaySfx(State.sfxRoundFail, 0.5)

    print(string.format("[Round] Round %d FAILED. earned=%s/%s, adWatched=%s, resetting",
        failedRound, earnedSnap, targetSnap, tostring(adWatched or false)))

    -- 符文精粹奖励（必须在 ResetToInitial 之前，需要 failedRound）
    local essenceReward = Runes.CalcEssenceReward(failedRound)
    if adWatched then
        essenceReward = essenceReward * 2
    end
    if essenceReward > 0 then
        gameState.runeEssence = (gameState.runeEssence or 0) + essenceReward
        print(string.format("[Rune] Essence +%d (total=%d)%s", essenceReward, gameState.runeEssence,
            adWatched and " [AD x2]" or ""))
    end
    SaveSystem.Save()  -- 持久化精粹/bestRound

    -- 完全重置到初始状态（保留 bestScore/bestRound/settings/棋盘布局/符文）
    State.ResetToInitial()
    Physics.RecalcLayout()
    Physics.InitPegs()

    -- 广告奖励：携带20%金币和宝石
    if adWatched and carryCoins then
        gameState.coins = gameState.coins + carryCoins
        if (carryGems or 0) > 0 then
            State.AddGems(carryGems)
        end
        print(string.format("[Rune] AD carry: coins +%s, gems +%d",
            tostring(carryCoins), carryGems or 0))
    end

    -- 财富符文：重置后加起始金币
    local wealthBonus = Runes.GetRuneValue("rune_wealth")
    if wealthBonus > 0 then
        gameState.coins = gameState.coins + wealthBonus
    end

    gameState.balls = {}

    -- 不阻塞，直接开始新一轮
    StartRound(gameState.round)

    -- 漂浮提示文字（纯视觉，不影响操作）
    local toastText = "时间到"
    if essenceReward > 0 then
        toastText = string.format("时间到  精粹+%d", essenceReward)
        if adWatched then
            toastText = toastText .. " (双倍)"
        end
    end
    gameState.failedToast = { timer = 2.5, text = toastText, offsetY = 0 }

    EventBus.emit("tab_changed")
end

-- ============================================================================
-- 模块间连接
-- ============================================================================
local function SetupModules()
    -- GameUI 需要 Physics 来投放钢珠
    GameUI.Physics = Physics

    -- 符文界面"重新开始"回调（支持广告模式）
    GameUI.OnRuneRestart = function(adWatched, carryCoins, carryGems)
        OnRoundFailed(adWatched, carryCoins, carryGems)
    end

    -- 新坑位解锁 → 重新计算物理布局
    EventBus.on("slot_added", function()
        Physics.RecalcLayout()
        Physics.InitPegs()
    end)
end

-- ============================================================================
-- 生命周期
-- ============================================================================
function Start()
    graphics.windowTitle = CONFIG.Title

    -- NanoVG 初始化
    State.vg = nvgCreate(1)
    if not State.vg then
        print("ERROR: Failed to create NanoVG context")
        return
    end
    State.fontNormal = nvgCreateFont(State.vg, "sans", "Fonts/MiSans-Regular.ttf")

    -- UI 库初始化
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 音效
    State.sfxScene_ = Scene()
    State.sfxPegHit = cache:GetResource("Sound", "audio/sfx/peg_hit.ogg")
    State.sfxSlotLand = cache:GetResource("Sound", "audio/sfx/slot_land.ogg")
    State.sfxBallDrop = cache:GetResource("Sound", "audio/sfx/ball_drop.ogg")
    State.sfxRoundSuccess = cache:GetResource("Sound", "audio/sfx/round_success.ogg")
    State.sfxRoundFail = cache:GetResource("Sound", "audio/sfx/round_fail.ogg")
    State.sfxButtonClick = cache:GetResource("Sound", "audio/sfx/button_click.ogg")

    -- BGM
    local bgmSound = cache:GetResource("Sound", "audio/bgm/bgm.ogg")
    if bgmSound then
        bgmSound.looped = true
        local bgmNode = State.sfxScene_:CreateChild("BGM")
        local bgmSource = bgmNode:CreateComponent("SoundSource")
        bgmSource.soundType = "Music"  -- 受 musicVolume 控制
        bgmSource.gain = 0.4
        bgmSource:Play(bgmSound)
        State.bgmSource = bgmSource
        print("[Audio] BGM started")
    else
        print("[Audio] BGM file not found, skipping")
    end

    -- 初始化坑位（10 个，初始等级 2 → x2倍率）
    gameState.slots = {}
    for i = 1, CONFIG.MAX_SLOTS do
        table.insert(gameState.slots, { kind = "good", level = 2 })
    end

    -- 模块间连接
    SetupModules()

    -- 布局、钉子（菜单阶段也需要物理布局数据）
    Physics.RecalcLayout()
    Physics.InitPegs()

    -- 事件订阅
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(State.vg, "NanoVGRender", "HandleNanoVGRender")

    -- 检测是否有存档（用于菜单按钮状态）
    gameState.hasSave = fileSystem:FileExists("save.json")
    gameState.showNewGameConfirm = false

    -- 从云端加载持久化字段（WASM 本地不持久化，必须从云端恢复）
    SaveSystem.LoadFromCloud(function(cloudData)
        if cloudData and gameState.gamePhase == "menu" then
            gameState.hasSave = true
            -- 恢复持久化字段到菜单态，不做完整 Deserialize（那由 StartGame 处理）
            gameState.bestScore = cloudData.bestScore and BigNum.deserialize(cloudData.bestScore) or gameState.bestScore
            gameState.bestRound = cloudData.bestRound or gameState.bestRound
            gameState.runeEssence = cloudData.runeEssence or 0
            if cloudData.runeLevels then
                gameState.runeLevels = SaveSystem._CopyTable(cloudData.runeLevels)
            end
            print(string.format("[Menu] Cloud persistent restored: essence=%d bestRound=%d",
                gameState.runeEssence, gameState.bestRound))
        elseif not gameState.hasSave then
            print("[Menu] No save found (local or cloud)")
        end
    end)
    print("[Menu] localSave=" .. tostring(gameState.hasSave))

    -- 不立即开始游戏，等待菜单点击
    -- UI 和第一轮在点击开始后创建

    -- 画质分级：auto 模式下移动端自动降级
    local q = gameState.settings.quality
    if q == "auto" then
        State.lowQuality = PlatformUtils.IsMobilePlatform()
    else
        State.lowQuality = (q == "low")
    end
    print("[Quality] mode=" .. q .. " lowQuality=" .. tostring(State.lowQuality))

    print("=== " .. CONFIG.Title .. " Started ===")
    print("Initial slots: " .. #gameState.slots)
end

function Stop()
    if State.vg then
        nvgDelete(State.vg)
        State.vg = nil
    end
    UI.Shutdown()
end

-- ============================================================================
-- 主循环
-- ============================================================================

--- 加载完成后真正开始游戏
local function BeginPlay()
    gameState.loading = false
    gameState.gamePhase = "playing"

    -- 从 bestScore 恢复排行榜保护阈值，防止低分覆盖
    Leaderboard.Init()

    -- 存档可能改变了 slots，重新计算布局
    Physics.RecalcLayout()
    Physics.InitPegs()

    GameUI.CreateUI()

    if gameState._hasRoundData then
        -- 存档含局内数据，恢复断点（时间/收益/目标已由 Deserialize 写入）
        gameState.roundPhase = "playing"
        gameState.popups = {}

        -- 恢复场上球
        if gameState._savedBalls then
            gameState.balls = gameState._savedBalls
            gameState._savedBalls = nil
        else
            gameState.balls = {}
        end

        -- 恢复钉子命中状态
        if gameState._savedPegTimers then
            local timers = gameState._savedPegTimers
            for i = 1, math.min(#gameState.pegs, #timers) do
                gameState.pegs[i].hitTimer = timers[i]
            end
            gameState._savedPegTimers = nil
        end

        gameState._hasRoundData = nil
        EventBus.emit("round_started", { round = gameState.round })
        print("[Menu] Resumed round " .. gameState.round
            .. " timeLeft=" .. string.format("%.0f", gameState.roundTimeLeft)
            .. " balls=" .. #gameState.balls)
    else
        StartRound(gameState.round)
        print("[Menu] Game started! round=" .. gameState.round)
    end
end

--- 从菜单进入游戏（比对本地与云端 saveCount，取更新的）
local function StartGame()
    if gameState.loading then return end
    gameState.loading = true
    Physics.PlaySfx(State.sfxButtonClick, 0.5)

    local localData = SaveSystem.LoadLocal()

    SaveSystem.LoadFromCloud(function(cloudData)
        local localCount = (localData and localData.saveCount) or 0
        local cloudCount = (cloudData and cloudData.saveCount) or 0

        if cloudData and cloudCount >= localCount then
            -- 云端更新（或相同），用云端
            SaveSystem.Deserialize(cloudData)
            SaveSystem.SaveLocal()  -- 同步到本地
            print("[Menu] Loaded from cloud (saveCount=" .. cloudCount .. " >= local=" .. localCount .. ")")
        elseif localData then
            -- 本地更新，用本地
            SaveSystem.Deserialize(localData)
            SaveSystem.SaveCloud()  -- 同步到云端
            print("[Menu] Loaded from local (saveCount=" .. localCount .. " > cloud=" .. cloudCount .. ")")
        else
            print("[Menu] No save, using defaults")
        end
        BeginPlay()
    end)
end

--- 通用矩形碰撞
local function HitRect(r, lx, ly)
    if not r then return false end
    return lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h
end

--- HUD 点击检测（模块级避免每帧分配闭包）
local function HandleHUDClick(lx, ly)
    if HitRect(Renderer.settingsBtnRect, lx, ly) then
        GameUI.ToggleSettings()
        return true
    end
    if HitRect(Renderer.lbBtnRect, lx, ly) then
        GameUI.ToggleLeaderboard()
        return true
    end
    return false
end

--- 菜单点击检测（前向声明，依赖 NewGame/StartGame 等）
local HandleMenuClick

--- 新游戏（重置状态，不加载存档）
local function NewGame()
    if gameState.loading then return end
    gameState.loading = true
    Physics.PlaySfx(State.sfxButtonClick, 0.5)
    State.ResetToInitial()
    gameState.loading = false
    -- 重建坑位布局
    Physics.RecalcLayout()
    Physics.InitPegs()
    BeginPlay()
    -- 保存一次（覆盖旧存档）
    SaveSystem.SaveLocal()
    SaveSystem.SaveCloud()
    print("[Menu] New game started!")
end

--- 菜单点击检测实现（模块级，避免每帧分配闭包）
HandleMenuClick = function(lx, ly)
    -- 弹窗优先处理
    if gameState.showNewGameConfirm then
        if HitRect(Renderer.dlgConfirmRect, lx, ly) then
            Physics.PlaySfx(State.sfxButtonClick, 0.5)
            gameState.showNewGameConfirm = false
            NewGame()
        elseif HitRect(Renderer.dlgCancelRect, lx, ly) then
            Physics.PlaySfx(State.sfxButtonClick, 0.5)
            gameState.showNewGameConfirm = false
        end
        return  -- 弹窗打开时不响应底层按钮
    end

    -- 继续游戏（有存档时可点）
    if gameState.hasSave and HitRect(Renderer.menuContinueRect, lx, ly) then
        StartGame()
        return
    end

    -- 新游戏
    if HitRect(Renderer.menuNewGameRect, lx, ly) then
        if gameState.hasSave then
            -- 有存档，弹确认窗
            Physics.PlaySfx(State.sfxButtonClick, 0.5)
            gameState.showNewGameConfirm = true
        else
            -- 无存档，直接新游戏
            NewGame()
        end
        return
    end

    -- 符文系统
    if HitRect(Renderer.menuRuneRect, lx, ly) then
        Physics.PlaySfx(State.sfxButtonClick, 0.5)
        gameState.gamePhase = "runes"
        return
    end
end

--- 符文界面点击
local function HandleRuneClick(lx, ly)
    -- 返回按钮
    if HitRect(Renderer.runeBackRect, lx, ly) then
        Physics.PlaySfx(State.sfxButtonClick, 0.5)
        gameState.gamePhase = "menu"
        Runes.scrollY = 0
        SaveSystem.Save()
        return
    end
    -- 升级按钮
    local runes = Runes.RUNE_DEFS
    for i, rune in ipairs(runes) do
        local rect = Renderer["runeUpgradeRect_" .. i]
        if rect and HitRect(rect, lx, ly) then
            if Runes.UpgradeRune(rune.id) then
                Physics.PlaySfx(State.sfxButtonClick, 0.5)
                SaveSystem.Save()
            end
            return
        end
    end
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- ==== 漂浮提示更新 ====
    if gameState.failedToast and gameState.failedToast.timer > 0 then
        gameState.failedToast.timer = gameState.failedToast.timer - dt
        gameState.failedToast.offsetY = gameState.failedToast.offsetY - dt * 30
        if gameState.failedToast.timer <= 0 then
            gameState.failedToast = nil
        end
    end

    -- ==== 菜单阶段 ====
    if gameState.gamePhase == "menu" then
        -- 鼠标点击检测
        if input:GetMouseButtonPress(MOUSEB_LEFT) then
            local dpr = graphics:GetDPR()
            local mx = input.mousePosition.x / dpr
            local my = input.mousePosition.y / dpr
            HandleMenuClick(mx, my)
        end
        -- 触摸检测
        for t = 0, input:GetNumTouches() - 1 do
            local touch = input:GetTouch(t)
            if touch and touch.pressure > 0 and touch.delta.x == 0 and touch.delta.y == 0 then
                local dpr = graphics:GetDPR()
                local tx = touch.position.x / dpr
                local ty = touch.position.y / dpr
                HandleMenuClick(tx, ty)
            end
        end
        return  -- 菜单阶段不更新游戏逻辑
    end

    -- ==== 符文阶段 ====
    if gameState.gamePhase == "runes" then
        -- 鼠标滚轮滚动
        local wheel = input:GetMouseMoveWheel()
        if wheel ~= 0 then
            Runes.scrollY = Runes.scrollY - wheel * State.S(40)
        end
        -- 触摸拖拽滚动
        for t = 0, input:GetNumTouches() - 1 do
            local touch = input:GetTouch(t)
            if touch and touch.pressure > 0 then
                local dpr = graphics:GetDPR()
                local dy = touch.delta.y / dpr
                if dy ~= 0 then
                    Runes.scrollY = Runes.scrollY - dy
                end
                -- 点击检测（无移动时视为点击）
                if touch.delta.x == 0 and touch.delta.y == 0 then
                    local tx = touch.position.x / dpr
                    local ty = touch.position.y / dpr
                    HandleRuneClick(tx, ty)
                end
            end
        end
        -- 鼠标点击
        if input:GetMouseButtonPress(MOUSEB_LEFT) then
            local dpr = graphics:GetDPR()
            local mx = input.mousePosition.x / dpr
            local my = input.mousePosition.y / dpr
            HandleRuneClick(mx, my)
        end
        return
    end

    -- ==== 游戏阶段 ====

    -- ---- Profiler 帧开始 ----
    Profiler.BeginFrame()

    -- 每帧开始清空效果缓存 + 设置帧时间戳
    Upgrades.BeginFrame()
    PegEffects.SetFrameTime(os.clock())

    -- 存档系统更新（云端节流写入 + 排行榜对比）
    Profiler.Begin("SaveSys")
    SaveSystem.Update(dt)
    Leaderboard.Update(dt)
    Profiler.End("SaveSys")

    Profiler.Begin("GameUI")
    GameUI.Update(dt)
    Profiler.End("GameUI")

    -- 暂停状态：只更新飘字动画，不推进游戏逻辑
    if gameState.paused then
        Physics.UpdatePopups(dt)
        Profiler.EndFrame(dt)
        return
    end

    -- 失败状态：更新飘字和过渡计时器，等待自动重试
    if gameState.roundPhase ~= "playing" then
        Physics.UpdatePopups(dt)
        if gameState.screenShake > 0 then
            gameState.screenShake = gameState.screenShake - dt
        end
        if gameState.roundTransitionTimer then
            gameState.roundTransitionTimer = gameState.roundTransitionTimer - dt
            if gameState.roundTransitionTimer <= 0 then
                gameState.roundTransitionTimer = nil
                StartRound(gameState.round)
            end
        end
        Profiler.EndFrame(dt)
        return
    end

    -- 倒计时
    gameState.roundTimeLeft = gameState.roundTimeLeft - dt

    -- 检查目标是否已达成（优先于超时判定）
    if gameState.roundEarned >= gameState.roundTarget then
        OnRoundSuccess()
        return
    end

    -- 检查时间是否已到
    if gameState.roundTimeLeft <= 0 then
        gameState.roundTimeLeft = 0
        OnRoundFailed()
        return
    end

    -- 空格键投弹
    if input:GetKeyPress(KEY_SPACE) then
        GameUI.HideTutorial()
        local dropped = Physics.DropMultipleBalls(true)
        if dropped == 0 then
            gameState.failedToast = { timer = 1.5, text = "金币不足", offsetY = 0 }
        end
    end

    gameState.pegSfxPlayed = false

    -- 自动投放（效果驱动）
    local autoLv = Upgrades.GetEffectLevel("auto_drop")
    if autoLv > 0 then
        local interval = Upgrades.GetEffectValue("auto_drop")
        gameState.autoDropTimer = gameState.autoDropTimer + dt
        if gameState.autoDropTimer >= interval then
            gameState.autoDropTimer = gameState.autoDropTimer - interval
            -- 精英投放：临时提升球品质
            local upgradeLv = Upgrades.GetEffectLevel("auto_drop_upgrade")
            local saved = gameState.selectedBallType
            if upgradeLv > 0 then
                local boost = math.floor(Upgrades.GetEffectValue("auto_drop_upgrade"))
                local upgraded = math.min(saved + boost, #Config.BALL_TYPES)
                -- 仅使用已解锁的球
                while upgraded > 1 and gameState.ballLevels[upgraded] == 0 do
                    upgraded = upgraded - 1
                end
                gameState.selectedBallType = upgraded
            end
            Physics.DropMultipleBalls()
            gameState.selectedBallType = saved
        end
    end

    -- 天降弹珠（效果驱动）
    local skyLv = Upgrades.GetEffectLevel("sky_drop")
    if skyLv > 0 then
        local interval = Upgrades.GetEffectValue("sky_drop")
        gameState.skyDropTimer = gameState.skyDropTimer + dt
        if gameState.skyDropTimer >= interval then
            gameState.skyDropTimer = gameState.skyDropTimer - interval
            Physics.DropSkyBall()
        end
    end

    Profiler.Begin("Settlement")
    Settlement.Update(dt)
    Profiler.End("Settlement")

    Profiler.Begin("Physics")
    Physics.UpdateBalls(dt)
    Profiler.End("Physics")

    Profiler.Begin("PegEffects")
    PegEffects.Update(dt)
    Profiler.End("PegEffects")

    Profiler.Begin("PegUpdate")
    Physics.UpdatePegs(dt)
    Profiler.End("PegUpdate")

    -- 将本帧累积的 number 收益一次性刷入 BigNum（减少 BigNum 运算次数）
    Profiler.Begin("FlushEarn")
    State.FlushEarnings()
    Profiler.End("FlushEarn")

    Profiler.Begin("Popups")
    Physics.UpdatePopups(dt)
    Profiler.End("Popups")

    if gameState.screenShake > 0 then
        gameState.screenShake = gameState.screenShake - dt
    end

    -- 节流刷新 UI（金币变动时标记脏，每 0.5 秒刷新一次）
    if State.uiDirty then
        State.uiDirtyTimer = State.uiDirtyTimer + dt
        if State.uiDirtyTimer >= 0.5 then
            State.uiDirty = false
            State.uiDirtyTimer = 0
            GameUI.RefreshAllItemsInCurrentTab()
        end
    end

    -- 鼠标点击检测
    if input:GetMouseButtonPress(MOUSEB_LEFT) then
        if not UI.IsPointerOverUI() then
            local dpr = graphics:GetDPR()
            local mx = input.mousePosition.x / dpr
            local my = input.mousePosition.y / dpr
            HandleHUDClick(mx, my)
        end
    end

    -- 触摸检测
    for t = 0, input:GetNumTouches() - 1 do
        local touch = input:GetTouch(t)
        if touch and touch.pressure > 0 and touch.delta.x == 0 and touch.delta.y == 0 then
            if not UI.IsPointerOverUI() then
                local dpr = graphics:GetDPR()
                local tx = touch.position.x / dpr
                local ty = touch.position.y / dpr
                HandleHUDClick(tx, ty)
            end
        end
    end

    -- ---- Profiler 帧结束 ----
    Profiler.EndFrame(dt)
end

--- NanoVG 渲染入口（全局函数，供事件系统调用）
function HandleNanoVGRender(eventType, eventData)
    Renderer.HandleNanoVGRender(eventType, eventData)
end
