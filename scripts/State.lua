-- ============================================================================
-- State.lua - 共享游戏状态（单例模式）
-- ============================================================================

local Config = require("Config")
local BigNum = require("BigNum")
local SecureValue = require("SecureValue")

local M = {}

--- 返回所有可重置的游戏状态初始值（失败时完全重置用）
--- 不包含 bestScore/bestRound/settings 等需要持久保留的字段
function M.GetInitialState()
    return {
        coins = BigNum.new(30),
        totalEarned = BigNum.new(0),
        gems = SecureValue.new(0),

        balls = {},
        selectedBallType = 1,
        ballLevels = { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },

        slots = {},         -- 由 main.lua 初始化具体内容

        autoDropTimer = 0,
        skyDropTimer = 0,

        activeTab = "balls",

        drawnEffects = { sky_drop = 1 },
        drawCount = 0,

        pegs = {},

        popups = {},
        screenShake = 0,

        comboCount = 0,
        comboTimer = 0,

        lastLandingSlot = 0,
        slotStreakCount = 0,

        -- 口袋大师流派状态
        slotCycleHistory = {},      -- 口袋轮转：连续不同口袋记录 {slotIndex, ...}
        slotVisitedThisRound = {},   -- 口袋大奖：本轮已访问口袋 {[slotIndex]=true}
        slotJackpotReady = false,    -- 口袋大奖：是否已触发全覆盖
        slotHitCountThisRound = {},  -- 热门口袋：本轮各口袋落入次数 {[slotIndex]=count}
        slotEchoBonuses = {},        -- 口袋回响：临时加成 {[slotIndex]={bonus=v, timer=t}}

        -- 聚财补强状态
        fortuneStackBonus = 0,       -- 聚财积累：本轮聚财比例累加值
        fortuneShareTimer = 0,       -- 聚财共享：辐射倒计时
        fortuneShareRatio = 0,       -- 聚财共享：最近一次聚财比例快照

        -- 暴击补强状态
        critStreakCount = 0,         -- 暴击连锁：连续暴击计数

        -- 连击爆发状态
        comboBurstCount = 0,         -- 连击爆发：本轮已触发次数

        -- 品质抽取系统
        pityCounter = 0,             -- 保底计数器（连续未出精良+）

        -- 附魔系统（本局有效，新游戏重置）
        ballEnchantments = {},       -- { [ballIndex] = "enchantId" } 当前球的附魔

        round = 1,
        roundTimeLeft = 60,
        roundEarned = BigNum.new(0),
        roundTarget = BigNum.new(20),
        roundPhase = "playing",
    }
end

--- 失败时完全重置到初始状态
--- 保留: bestScore, bestRound, settings, gamePhase, 棋盘布局, NanoVG/音效资源
function M.ResetToInitial()
    local init = M.GetInitialState()
    for k, v in pairs(init) do
        M.gameState[k] = v
    end
    -- 重建坑位
    M.gameState.slots = {}
    for i = 1, Config.CONFIG.MAX_SLOTS do
        table.insert(M.gameState.slots, { kind = "good", level = 2 })
    end
    M.uiDirty = true
    print("[State] Full reset to initial state")
end

-- 游戏状态（基于 GetInitialState 初始化，合并持久化字段）
M.gameState = M.GetInitialState()

-- 持久化字段（不被 ResetToInitial 覆盖）
M.gameState.bestScore = BigNum.new(0)
M.gameState.bestRound = 0
M.gameState.saveCount = 0  -- 存档写入计数器（用于本地/云端比对）

-- 皮肤系统（持久化，不随游戏失败/新游戏重置）
M.gameState.ballSkins = {}        -- { [ballIndex] = "skinId" } 当前激活的皮肤
M.gameState.unlockedSkins = {}    -- { ["ballIndex_skinId"] = true } 解锁记录

-- 符文系统（持久化，不随 ResetToInitial 重置）
M.gameState.runeEssence = 0       -- 符文精粹余额（普通 number）
M.gameState.runeLevels = {}        -- { [runeId] = level }

-- 游戏阶段
M.gameState.gamePhase = "menu"
M.gameState.loading = false
M.gameState.paused = false

-- 用户设置
M.gameState.settings = {
    sfxVolume = 1.0,
    musicVolume = 1.0,
    shakeEnabled = true,
    quality = "auto",  -- "high" | "low" | "auto"（auto 根据平台自动选择）
}

--- 当前生效画质（运行时计算，避免每帧判断 auto）
M.lowQuality = false

-- 棋盘布局（运行时计算）
M.gameState.boardLeft = 0
M.gameState.boardRight = 0
M.gameState.boardTop = 0
M.gameState.boardBottom = 0
M.gameState.slotWidth = 0

-- NanoVG 上下文与字体
M.vg = nil
M.fontNormal = -1

-- 音效资源
M.sfxPegHit = nil
M.sfxSlotLand = nil
M.sfxBallDrop = nil
M.sfxScene_ = nil

-- UI 引用
M.uiRoot_ = nil
M.roundPopup_ = nil

-- UI 刷新节流
M.uiDirty = false
M.uiDirtyTimer = 0

-- UI 缩放系数（基于参考宽度 320 逻辑像素，手机端 ≈1.2，PC 端按比例放大）
M.uiScale = 1.0

--- 更新 UI 缩放系数（每帧或分辨率变化时调用）
function M.UpdateUIScale()
    local physW = graphics:GetWidth()
    local dpr = graphics:GetDPR()
    local logicalW = physW / dpr
    M.uiScale = logicalW / 320
end

--- 按 uiScale 缩放像素值的快捷函数
---@param px number 设计稿像素值（基于 400px 宽度设计）
---@return number 缩放后的像素值
function M.S(px)
    return px * M.uiScale
end

-- ============================================================================
-- 收益累加器（热路径优化）
-- 撞钉期间先累积 number 增量，帧末 FlushEarnings 一次性加到 BigNum
-- ============================================================================
M._pendingEarnings = 0  -- number 类型累加器

--- 统一收益入账（同时更新 coins, totalEarned, roundEarned）
--- 热路径调用时仅累加到 number 缓冲区，大幅减少 BigNum 运算
---@param amount number|table  普通 number 或 BigNum
function M.AddEarnings(amount)
    -- BigNum 参数走原来的路径
    if BigNum.is(amount) then
        M.gameState.coins = M.gameState.coins + amount
        M.gameState.totalEarned = M.gameState.totalEarned + amount
        if M.gameState.roundPhase == "playing" then
            M.gameState.roundEarned = M.gameState.roundEarned + amount
        end
        M.uiDirty = true
        return
    end
    -- 普通 number → 累加到缓冲区（零开销）
    M._pendingEarnings = M._pendingEarnings + amount
    M.uiDirty = true
end

--- 将累积的 number 收益一次性刷入 BigNum 字段（每帧调用一次）
function M.FlushEarnings()
    local pending = M._pendingEarnings
    if pending == 0 then return end
    M._pendingEarnings = 0
    M.gameState.coins = M.gameState.coins + pending
    M.gameState.totalEarned = M.gameState.totalEarned + pending
    if M.gameState.roundPhase == "playing" then
        M.gameState.roundEarned = M.gameState.roundEarned + pending
    end
end

--- 获取当前宝石数量（解密读取）
---@return integer
function M.GetGems()
    return SecureValue.get(M.gameState.gems)
end

--- 设置宝石数量（加密写入）
---@param v integer
function M.SetGems(v)
    SecureValue.set(M.gameState.gems, v)
    M.uiDirty = true
end

--- 增加宝石
---@param delta integer
function M.AddGems(delta)
    SecureValue.add(M.gameState.gems, delta)
    M.uiDirty = true
end

--- 消耗宝石（检查余额，成功返回 true）
---@param cost integer
---@return boolean
function M.SpendGems(cost)
    if M.GetGems() < cost then return false end
    SecureValue.add(M.gameState.gems, -cost)
    M.uiDirty = true
    return true
end

--- 将音量设置应用到引擎音频系统
function M.ApplyAudioSettings()
    if audio then
        audio:SetMasterGain(SOUND_EFFECT, M.gameState.settings.sfxVolume)
        audio:SetMasterGain(SOUND_MUSIC, M.gameState.settings.musicVolume)
    end
end

--- 数字格式化（Clicker Titans 风格，支持 BigNum 和普通数字）
function M.FormatNumber(n)
    return BigNum.format(n)
end

return M
