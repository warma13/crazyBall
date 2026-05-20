-- ============================================================================
-- SaveSystem.lua - 存读档系统
-- 云端读 → 本地缓存 → 同步写本地 + 异步写云端
-- ============================================================================

---@diagnostic disable-next-line: undefined-global
local cjson = cjson
local Config = require("Config")
local BigNum = require("BigNum")
local State = require("State")
local EventBus = require("EventBus")

local gameState = State.gameState

local M = {}

local SecureValue = require("SecureValue")

local SAVE_FILE = "save.json"
local SAVE_VERSION = 4  -- 当前存档版本号（v4: 放置模式字段）
local SIGN_SALT = "cRz7$pBm!2xQ"  -- 签名盐值
local CLOUD_THROTTLE_NORMAL = 30  -- 普通保存节流（秒）
local CLOUD_THROTTLE_URGENT = 5   -- 紧急保存节流（广告奖励/手动保存）
local RANK_CHECK_INTERVAL = 15  -- 排行榜对比间隔（秒）

-- ============================================================================
-- 分 key 云端存储
-- 每个模块使用独立的 cloud key，加载/保存互不干扰
-- ============================================================================
local CLOUD_KEYS = {
    shared = "save_shared",
    main   = "save_main",
    runes  = "save_runes",
    idle   = "save_idle",
}
local CLOUD_KEY_LEGACY = "save_data"  -- 旧版单 key（用于迁移）

local cloudDirty = false
local cloudUrgent = false  -- true = 5s 紧急节流, false = 30s 普通节流
local cloudTimer = 0
local rankCheckTimer = 0

-- ============================================================================
-- WASM 云存档安全保护
-- WASM 环境无持久化本地存储，云端是唯一的存档来源。
-- 必须在云端加载成功后才允许写入，防止空数据覆盖玩家存档。
-- ============================================================================
local cloudLoadSucceeded = false  -- 云端存档是否已成功加载（或确认无存档）

-- 云加载配置
local CLOUD_CACHE_TTL = 30       -- 云端数据缓存有效期（秒）

-- 云端数据缓存（per-key，避免短时间内重复请求）
---@type table<string, { data: table|nil, hasData: boolean, timestamp: number }>
local _cloudCache = {}

--- 获取或创建指定 key 的缓存条目
---@param key string
---@return table
local function _getCache(key)
    if not _cloudCache[key] then
        _cloudCache[key] = { data = nil, hasData = false, timestamp = 0 }
    end
    return _cloudCache[key]
end

-- 保存状态指示器
-- status: nil | "saving" | "saved" | "failed"
local saveIndicator = {
    status = nil,
    timer = 0,        -- 飘字显示倒计时
    fadeTime = 2.0,   -- 飘字持续秒数
}

-- ============================================================================
-- 序列化 / 反序列化
-- ============================================================================

--- 从 gameState 提取需要持久化的字段
function M.Serialize()
    gameState.saveCount = (gameState.saveCount or 0) + 1
    -- 保存前同步当前关卡的球币到 idleLevelData
    State.FlushIdleEarnings()
    local lv = gameState.idleLevel
    if gameState.idleLevelData[lv] then
        gameState.idleLevelData[lv].ballCoins = gameState.idleBallCoins
        gameState.idleLevelData[lv].ballsDropped = gameState.idleBallsDropped
    end
    local data = {
        version = SAVE_VERSION,
        saveCount = gameState.saveCount,
        coins = BigNum.serialize(gameState.coins),
        totalEarned = BigNum.serialize(gameState.totalEarned),
        bestScore = BigNum.serialize(gameState.bestScore),
        gems = State.GetGems(),
        round = gameState.round,
        selectedBallType = gameState.selectedBallType,
        ballLevels = M._CopyArray(gameState.ballLevels),
        slots = M._CopySlots(gameState.slots),
        drawnEffects = M._CopyTable(gameState.drawnEffects),
        drawCount = gameState.drawCount,
        pityCounter = gameState.pityCounter,
        bestRound = gameState.bestRound,
        settings = {
            sfxVolume = gameState.settings.sfxVolume,
            musicVolume = gameState.settings.musicVolume,
            shakeEnabled = gameState.settings.shakeEnabled,
        },
        ballSkins = M._CopyTable(gameState.ballSkins),
        unlockedSkins = M._CopyTable(gameState.unlockedSkins),

        -- 符文系统
        runeEssence = gameState.runeEssence or 0,
        runeLevels = M._CopyTable(gameState.runeLevels or {}),

        -- 放置模式
        idleCoins = BigNum.serialize(gameState.idleCoins),
        idleTotalEarned = BigNum.serialize(gameState.idleTotalEarned),
        idleBallLevels = M._CopyArray(gameState.idleBallLevels),
        idleSelectedBall = gameState.idleSelectedBall,
        idleSlots = M._CopySlots(gameState.idleSlots),
        idleDrawnEffects = M._CopyTable(gameState.idleDrawnEffects),
        idleDrawCount = gameState.idleDrawCount,
        idleDrawPity = gameState.idleDrawPity,
        idlePrestigeCount = gameState.idlePrestigeCount,
        idlePrestigeMult = gameState.idlePrestigeMult,
        idleStardust = gameState.idleStardust,
        idlePrestigeAbilities = M._CopyTable(gameState.idlePrestigeAbilities),
        idleBallAbilityLevels = M._CopyTable(gameState.idleBallAbilityLevels),
        idleUpgradeLevels = M._CopyTable(gameState.idleUpgradeLevels),
        idleSkills = M._CopyTable(gameState.idleSkills),
        idleSkillPickCount = gameState.idleSkillPickCount,
        idleSkillCooldowns = (function()
            local ok, IdleMode = pcall(require, "IdleMode")
            if ok and IdleMode.ExportSkillCooldowns then
                return IdleMode.ExportSkillCooldowns()
            end
            return {}
        end)(),

        -- 关卡系统
        idleLevel = gameState.idleLevel,
        idleMaxUnlockedLevel = gameState.idleMaxUnlockedLevel,
        idleBallsDropped = gameState.idleBallsDropped,
        idleBallCoins = BigNum.serialize(gameState.idleBallCoins),
        idleTotalBallCoins = BigNum.serialize(gameState.idleTotalBallCoins),
        idleGlobalBallValueBonus = gameState.idleGlobalBallValueBonus,
        idleGlobalSlotMultBonus = gameState.idleGlobalSlotMultBonus,
        idleLevelData = M._SerializeLevelData(gameState.idleLevelData, gameState.idleLevel),

        -- 附魔系统（全局 { [enchantId] = level }）
        idleEnchantments = M._CopyTable(gameState.idleEnchantments or {}),

        -- 免广券
        adFreeTickets = gameState.adFreeTickets or 0,
    }

    -- 局内状态：仅主线 playing 时保存（放置模式下省略，瘦身）
    if gameState.roundPhase == "playing" and gameState.gamePhase ~= "idle" then
        data.roundTimeLeft = gameState.roundTimeLeft
        data.roundEarned = BigNum.serialize(gameState.roundEarned)
        data.roundTarget = BigNum.serialize(gameState.roundTarget)
        data.roundPhase = gameState.roundPhase
        data.comboCount = gameState.comboCount
        -- comboTimer 是瞬态值，不保存
        -- 场上球状态
        local balls = M._SerializeBalls(gameState.balls)
        if #balls > 0 then data.balls = balls end
        -- 钉子命中状态（稀疏格式，仅非零值）
        data.pegHitTimers = M._SerializePegTimers(gameState.pegs)
    end

    return data
end

-- ============================================================================
-- 分模块序列化（与分模块反序列化对称，每个模块只序列化自己的字段）
-- ============================================================================

--- 序列化共享字段（所有模式都需要）
function M.SerializeShared()
    gameState.saveCount = (gameState.saveCount or 0) + 1
    return {
        version = SAVE_VERSION,
        saveCount = gameState.saveCount,
        bestScore = BigNum.serialize(gameState.bestScore),
        bestRound = gameState.bestRound,
        gems = State.GetGems(),
        settings = {
            sfxVolume = gameState.settings.sfxVolume,
            musicVolume = gameState.settings.musicVolume,
            shakeEnabled = gameState.settings.shakeEnabled,
        },
        adFreeTickets = gameState.adFreeTickets or 0,
    }
end

--- 序列化主线游戏字段
function M.SerializeMainGame()
    local data = {
        coins = BigNum.serialize(gameState.coins),
        totalEarned = BigNum.serialize(gameState.totalEarned),
        round = gameState.round,
        selectedBallType = gameState.selectedBallType,
        ballLevels = M._CopyArray(gameState.ballLevels),
        slots = M._CopySlots(gameState.slots),
        drawnEffects = M._CopyTable(gameState.drawnEffects),
        drawCount = gameState.drawCount,
        pityCounter = gameState.pityCounter,
        ballSkins = M._CopyTable(gameState.ballSkins),
        unlockedSkins = M._CopyTable(gameState.unlockedSkins),

        -- 符文（主线也需要，符文加成影响主线）
        runeEssence = gameState.runeEssence or 0,
        runeLevels = M._CopyTable(gameState.runeLevels or {}),
    }

    -- 局内状态：仅 playing 时保存
    if gameState.roundPhase == "playing" and gameState.gamePhase ~= "idle" then
        data.roundTimeLeft = gameState.roundTimeLeft
        data.roundEarned = BigNum.serialize(gameState.roundEarned)
        data.roundTarget = BigNum.serialize(gameState.roundTarget)
        data.roundPhase = gameState.roundPhase
        data.comboCount = gameState.comboCount
        local balls = M._SerializeBalls(gameState.balls)
        if #balls > 0 then data.balls = balls end
        data.pegHitTimers = M._SerializePegTimers(gameState.pegs)
    end

    return data
end

--- 序列化符文字段
function M.SerializeRunes()
    return {
        runeEssence = gameState.runeEssence or 0,
        runeLevels = M._CopyTable(gameState.runeLevels or {}),
        bestRound = gameState.bestRound,
    }
end

--- 序列化放置模式字段
function M.SerializeIdle()
    -- 保存前同步当前关卡的球币到 idleLevelData
    State.FlushIdleEarnings()
    local lv = gameState.idleLevel
    if gameState.idleLevelData[lv] then
        gameState.idleLevelData[lv].ballCoins = gameState.idleBallCoins
        gameState.idleLevelData[lv].ballsDropped = gameState.idleBallsDropped
    end
    return {
        idleCoins = BigNum.serialize(gameState.idleCoins),
        idleTotalEarned = BigNum.serialize(gameState.idleTotalEarned),
        idleBallLevels = M._CopyArray(gameState.idleBallLevels),
        idleSelectedBall = gameState.idleSelectedBall,
        idleSlots = M._CopySlots(gameState.idleSlots),
        idleDrawnEffects = M._CopyTable(gameState.idleDrawnEffects),
        idleDrawCount = gameState.idleDrawCount,
        idleDrawPity = gameState.idleDrawPity,
        idlePrestigeCount = gameState.idlePrestigeCount,
        idlePrestigeMult = gameState.idlePrestigeMult,
        idleStardust = gameState.idleStardust,
        idlePrestigeAbilities = M._CopyTable(gameState.idlePrestigeAbilities),
        idleBallAbilityLevels = M._CopyTable(gameState.idleBallAbilityLevels),
        idleUpgradeLevels = M._CopyTable(gameState.idleUpgradeLevels),
        idleSkills = M._CopyTable(gameState.idleSkills),
        idleSkillPickCount = gameState.idleSkillPickCount,
        idleSkillCooldowns = (function()
            local ok, IdleMode = pcall(require, "IdleMode")
            if ok and IdleMode.ExportSkillCooldowns then
                return IdleMode.ExportSkillCooldowns()
            end
            return {}
        end)(),

        -- 关卡系统
        idleLevel = gameState.idleLevel,
        idleMaxUnlockedLevel = gameState.idleMaxUnlockedLevel,
        idleBallsDropped = gameState.idleBallsDropped,
        idleBallCoins = BigNum.serialize(gameState.idleBallCoins),
        idleTotalBallCoins = BigNum.serialize(gameState.idleTotalBallCoins),
        idleGlobalBallValueBonus = gameState.idleGlobalBallValueBonus,
        idleGlobalSlotMultBonus = gameState.idleGlobalSlotMultBonus,
        idleLevelData = M._SerializeLevelData(gameState.idleLevelData, gameState.idleLevel),

        -- 附魔系统
        idleEnchantments = M._CopyTable(gameState.idleEnchantments or {}),
    }
end

--- 将存档数据应用到 gameState
function M.Deserialize(data)
    if not data then return end

    gameState.coins = BigNum.deserialize(data.coins or 15)
    gameState.totalEarned = BigNum.deserialize(data.totalEarned or 0)
    gameState.bestScore = BigNum.deserialize(data.bestScore or 0)
    State.SetGems(data.gems or 0)
    gameState.round = data.round or 1
    gameState.selectedBallType = data.selectedBallType or 1
    gameState.drawCount = data.drawCount or 0
    gameState.pityCounter = data.pityCounter or 0
    gameState.bestRound = data.bestRound or 0
    gameState.saveCount = data.saveCount or 0

    -- ballLevels（动态适配球数量）
    if data.ballLevels then
        local ballCount = #Config.BALL_TYPES
        for i = 1, ballCount do
            gameState.ballLevels[i] = data.ballLevels[i] or 0
        end
    end

    -- slots
    if data.slots then
        for i = 1, #data.slots do
            if gameState.slots[i] then
                gameState.slots[i].kind = data.slots[i].kind or "good"
                gameState.slots[i].level = data.slots[i].level or 2
            end
        end
    end

    -- drawnEffects
    if data.drawnEffects then
        -- 存档迁移：double_hit → peg_resonance
        if data.drawnEffects["double_hit"] then
            data.drawnEffects["peg_resonance"] = data.drawnEffects["double_hit"]
            data.drawnEffects["double_hit"] = nil
        end
        -- 存档迁移：big_ball → peg_bonus
        if data.drawnEffects["big_ball"] then
            data.drawnEffects["peg_bonus"] = data.drawnEffects["big_ball"]
            data.drawnEffects["big_ball"] = nil
        end
        gameState.drawnEffects = M._CopyTable(data.drawnEffects)
    end

    -- settings
    if data.settings then
        if data.settings.sfxVolume ~= nil then
            gameState.settings.sfxVolume = data.settings.sfxVolume
        end
        if data.settings.musicVolume ~= nil then
            gameState.settings.musicVolume = data.settings.musicVolume
        end
        if data.settings.shakeEnabled ~= nil then
            gameState.settings.shakeEnabled = data.settings.shakeEnabled
        end
    end

    -- 皮肤数据（JSON 会将数字 key 转为字符串，需恢复为数字 key）
    if data.ballSkins then
        gameState.ballSkins = {}
        for k, v in pairs(data.ballSkins) do
            gameState.ballSkins[tonumber(k) or k] = v
        end
    end
    if data.unlockedSkins then
        gameState.unlockedSkins = M._CopyTable(data.unlockedSkins)
    end

    -- 符文系统
    gameState.runeEssence = data.runeEssence or 0
    if data.runeLevels then
        gameState.runeLevels = M._CopyTable(data.runeLevels)
    end

    -- 放置模式（v4+）
    if data.idleCoins then
        gameState.idleCoins = BigNum.deserialize(data.idleCoins)
    end
    if data.idleTotalEarned then
        gameState.idleTotalEarned = BigNum.deserialize(data.idleTotalEarned)
    end
    if data.idleBallLevels then
        local ballCount = #Config.BALL_TYPES
        for i = 1, ballCount do
            gameState.idleBallLevels[i] = data.idleBallLevels[i] or 0
        end
    end
    gameState.idleSelectedBall = data.idleSelectedBall or 1
    if data.idleSlots then
        gameState.idleSlots = {}
        for i = 1, #data.idleSlots do
            gameState.idleSlots[i] = {
                kind = data.idleSlots[i].kind or "good",
                level = data.idleSlots[i].level or 2,
            }
        end
    end
    if data.idleDrawnEffects then
        gameState.idleDrawnEffects = M._CopyTable(data.idleDrawnEffects)
    end
    gameState.idleDrawCount = data.idleDrawCount or 0
    gameState.idleDrawPity = data.idleDrawPity or 0
    gameState.idlePrestigeCount = data.idlePrestigeCount or 0
    gameState.idlePrestigeMult = data.idlePrestigeMult or 1.0
    gameState.idleStardust = data.idleStardust or 0
    if data.idlePrestigeAbilities then
        gameState.idlePrestigeAbilities = M._CopyTable(data.idlePrestigeAbilities)
    end
    if data.idleBallAbilityLevels then
        gameState.idleBallAbilityLevels = M._CopyTable(data.idleBallAbilityLevels)
    end
    if data.idleUpgradeLevels then
        gameState.idleUpgradeLevels = M._CopyTable(data.idleUpgradeLevels)
    end
    if data.idleSkills then
        gameState.idleSkills = M._CopyTable(data.idleSkills)
    end
    gameState.idleSkillPickCount = data.idleSkillPickCount or 0
    gameState._savedSkillCooldowns = data.idleSkillCooldowns or nil

    -- 关卡系统恢复
    gameState.idleLevel = data.idleLevel or 1
    gameState.idleMaxUnlockedLevel = data.idleMaxUnlockedLevel or 1
    gameState.idleBallsDropped = data.idleBallsDropped or 0
    if data.idleBallCoins then
        gameState.idleBallCoins = BigNum.deserialize(data.idleBallCoins)
    end
    if data.idleTotalBallCoins then
        gameState.idleTotalBallCoins = BigNum.deserialize(data.idleTotalBallCoins)
    end
    gameState.idleGlobalBallValueBonus = data.idleGlobalBallValueBonus or 0
    gameState.idleGlobalSlotMultBonus = data.idleGlobalSlotMultBonus or 0
    if data.idleLevelData then
        gameState.idleLevelData = M._DeserializeLevelData(data.idleLevelData)
    end

    -- 附魔系统恢复（全局格式）
    if data.idleEnchantments then
        gameState.idleEnchantments = M._CopyTable(data.idleEnchantments)
    elseif data.ballEnchantments then
        -- 旧存档迁移：合并所有球的附魔，取各附魔最高等级
        gameState.idleEnchantments = {}
        for ballIdxStr, map in pairs(data.ballEnchantments) do
            if type(map) == "table" then
                for enchantId, lv in pairs(map) do
                    if enchantId ~= "gem_chance" then  -- 过滤已删除的附魔
                        local cur = gameState.idleEnchantments[enchantId] or 0
                        if lv > cur then
                            gameState.idleEnchantments[enchantId] = lv
                        end
                    end
                end
            end
        end
        print("[Save] Migrated per-ball enchantments to global format")
    end

    -- 免广券
    gameState.adFreeTickets = data.adFreeTickets or 0

    -- 局内状态恢复
    if data.roundTimeLeft then
        gameState.roundTimeLeft = data.roundTimeLeft
    end
    if data.roundEarned then
        gameState.roundEarned = BigNum.deserialize(data.roundEarned)
    end
    if data.roundTarget then
        gameState.roundTarget = BigNum.deserialize(data.roundTarget)
    end
    if data.roundPhase then
        gameState.roundPhase = data.roundPhase
    end
    gameState.comboCount = data.comboCount or 0
    gameState.comboTimer = data.comboTimer or 0

    -- 恢复场上球
    if data.balls and #data.balls > 0 then
        gameState._savedBalls = M._DeserializeBalls(data.balls)
    end
    -- 恢复钉子命中状态
    if data.pegHitTimers then
        gameState._savedPegTimers = data.pegHitTimers
    end

    -- 标记存档包含局内数据（供 BeginPlay 判断是否跳过 StartRound 重置）
    gameState._hasRoundData = (data.roundTimeLeft ~= nil)

    -- 特定用户免广券赠送
    local AD_FREE_USERS = { [413248871] = 10000, [1779057459] = 10000 }
    local uid = clientCloud and clientCloud.userId
    -- userId 可能是字符串，转为数字匹配
    local uidNum = tonumber(uid)
    if uidNum and AD_FREE_USERS[uidNum] then
        local grant = AD_FREE_USERS[uidNum]
        if (gameState.adFreeTickets or 0) < grant then
            gameState.adFreeTickets = grant
            print("[Save] Granted " .. grant .. " ad-free tickets to user " .. uid)
        end
    end

    -- 应用音频设置到引擎
    State.ApplyAudioSettings()

    print("[Save] Deserialized: coins=" .. gameState.coins
        .. " gems=" .. State.GetGems()
        .. " round=" .. gameState.round)
end

-- ============================================================================
-- 分模块反序列化（按需加载，避免每次加载全部数据）
-- ============================================================================

--- 反序列化共享/设置字段（所有模式都需要）
function M.DeserializeShared(data)
    if not data then return end
    gameState.saveCount = data.saveCount or 0
    gameState.bestScore = BigNum.deserialize(data.bestScore or 0)
    gameState.bestRound = data.bestRound or 0
    gameState.adFreeTickets = data.adFreeTickets or 0
    State.SetGems(data.gems or 0)

    if data.settings then
        if data.settings.sfxVolume ~= nil then
            gameState.settings.sfxVolume = data.settings.sfxVolume
        end
        if data.settings.musicVolume ~= nil then
            gameState.settings.musicVolume = data.settings.musicVolume
        end
        if data.settings.shakeEnabled ~= nil then
            gameState.settings.shakeEnabled = data.settings.shakeEnabled
        end
    end

    -- 特定用户免广券赠送
    local AD_FREE_USERS = { [413248871] = 10000, [1779057459] = 10000 }
    local uid = clientCloud and clientCloud.userId
    local uidNum = tonumber(uid)
    if uidNum and AD_FREE_USERS[uidNum] then
        local grant = AD_FREE_USERS[uidNum]
        if (gameState.adFreeTickets or 0) < grant then
            gameState.adFreeTickets = grant
            print("[Save] Granted " .. grant .. " ad-free tickets to user " .. uid)
        end
    end

    State.ApplyAudioSettings()
    print("[Save] DeserializeShared: bestRound=" .. gameState.bestRound)
end

--- 反序列化主线游戏字段
function M.DeserializeMainGame(data)
    if not data then return end
    gameState.coins = BigNum.deserialize(data.coins or 15)
    gameState.totalEarned = BigNum.deserialize(data.totalEarned or 0)
    gameState.round = data.round or 1
    gameState.selectedBallType = data.selectedBallType or 1
    gameState.drawCount = data.drawCount or 0
    gameState.pityCounter = data.pityCounter or 0

    -- ballLevels
    if data.ballLevels then
        local ballCount = #Config.BALL_TYPES
        for i = 1, ballCount do
            gameState.ballLevels[i] = data.ballLevels[i] or 0
        end
    end

    -- slots
    if data.slots then
        for i = 1, #data.slots do
            if gameState.slots[i] then
                gameState.slots[i].kind = data.slots[i].kind or "good"
                gameState.slots[i].level = data.slots[i].level or 2
            end
        end
    end

    -- drawnEffects
    if data.drawnEffects then
        if data.drawnEffects["double_hit"] then
            data.drawnEffects["peg_resonance"] = data.drawnEffects["double_hit"]
            data.drawnEffects["double_hit"] = nil
        end
        if data.drawnEffects["big_ball"] then
            data.drawnEffects["peg_bonus"] = data.drawnEffects["big_ball"]
            data.drawnEffects["big_ball"] = nil
        end
        gameState.drawnEffects = M._CopyTable(data.drawnEffects)
    end

    -- 皮肤
    if data.ballSkins then
        gameState.ballSkins = {}
        for k, v in pairs(data.ballSkins) do
            gameState.ballSkins[tonumber(k) or k] = v
        end
    end
    if data.unlockedSkins then
        gameState.unlockedSkins = M._CopyTable(data.unlockedSkins)
    end

    -- 符文（主线也需要，因为符文加成影响主线）
    gameState.runeEssence = data.runeEssence or 0
    if data.runeLevels then
        gameState.runeLevels = M._CopyTable(data.runeLevels)
    end

    -- 局内状态恢复
    if data.roundTimeLeft then
        gameState.roundTimeLeft = data.roundTimeLeft
    end
    if data.roundEarned then
        gameState.roundEarned = BigNum.deserialize(data.roundEarned)
    end
    if data.roundTarget then
        gameState.roundTarget = BigNum.deserialize(data.roundTarget)
    end
    if data.roundPhase then
        gameState.roundPhase = data.roundPhase
    end
    gameState.comboCount = data.comboCount or 0
    gameState.comboTimer = data.comboTimer or 0

    if data.balls and #data.balls > 0 then
        gameState._savedBalls = M._DeserializeBalls(data.balls)
    end
    if data.pegHitTimers then
        gameState._savedPegTimers = data.pegHitTimers
    end
    gameState._hasRoundData = (data.roundTimeLeft ~= nil)

    print("[Save] DeserializeMainGame: coins=" .. gameState.coins .. " round=" .. gameState.round)
end

--- 反序列化符文字段
function M.DeserializeRunes(data)
    if not data then return end
    gameState.runeEssence = data.runeEssence or 0
    if data.runeLevels then
        gameState.runeLevels = M._CopyTable(data.runeLevels)
    end
    gameState.bestRound = data.bestRound or gameState.bestRound
    print("[Save] DeserializeRunes: essence=" .. gameState.runeEssence)
end

--- 反序列化放置模式字段
function M.DeserializeIdle(data)
    if not data then return end

    if data.idleCoins then
        gameState.idleCoins = BigNum.deserialize(data.idleCoins)
    end
    if data.idleTotalEarned then
        gameState.idleTotalEarned = BigNum.deserialize(data.idleTotalEarned)
    end
    if data.idleBallLevels then
        local ballCount = #Config.BALL_TYPES
        for i = 1, ballCount do
            gameState.idleBallLevels[i] = data.idleBallLevels[i] or 0
        end
    end
    gameState.idleSelectedBall = data.idleSelectedBall or 1
    if data.idleSlots then
        gameState.idleSlots = {}
        for i = 1, #data.idleSlots do
            gameState.idleSlots[i] = {
                kind = data.idleSlots[i].kind or "good",
                level = data.idleSlots[i].level or 2,
            }
        end
    end
    if data.idleDrawnEffects then
        gameState.idleDrawnEffects = M._CopyTable(data.idleDrawnEffects)
    end
    gameState.idleDrawCount = data.idleDrawCount or 0
    gameState.idleDrawPity = data.idleDrawPity or 0
    gameState.idlePrestigeCount = data.idlePrestigeCount or 0
    gameState.idlePrestigeMult = data.idlePrestigeMult or 1.0
    gameState.idleStardust = data.idleStardust or 0
    if data.idlePrestigeAbilities then
        gameState.idlePrestigeAbilities = M._CopyTable(data.idlePrestigeAbilities)
    end
    if data.idleBallAbilityLevels then
        gameState.idleBallAbilityLevels = M._CopyTable(data.idleBallAbilityLevels)
    end
    if data.idleUpgradeLevels then
        gameState.idleUpgradeLevels = M._CopyTable(data.idleUpgradeLevels)
    end
    if data.idleSkills then
        gameState.idleSkills = M._CopyTable(data.idleSkills)
    end
    gameState.idleSkillPickCount = data.idleSkillPickCount or 0
    gameState._savedSkillCooldowns = data.idleSkillCooldowns or nil

    -- 关卡系统
    gameState.idleLevel = data.idleLevel or 1
    gameState.idleMaxUnlockedLevel = data.idleMaxUnlockedLevel or 1
    gameState.idleBallsDropped = data.idleBallsDropped or 0
    if data.idleBallCoins then
        gameState.idleBallCoins = BigNum.deserialize(data.idleBallCoins)
    end
    if data.idleTotalBallCoins then
        gameState.idleTotalBallCoins = BigNum.deserialize(data.idleTotalBallCoins)
    end
    gameState.idleGlobalBallValueBonus = data.idleGlobalBallValueBonus or 0
    gameState.idleGlobalSlotMultBonus = data.idleGlobalSlotMultBonus or 0
    if data.idleLevelData then
        gameState.idleLevelData = M._DeserializeLevelData(data.idleLevelData)
    end

    -- 附魔系统
    if data.idleEnchantments then
        gameState.idleEnchantments = M._CopyTable(data.idleEnchantments)
    elseif data.ballEnchantments then
        gameState.idleEnchantments = {}
        for ballIdxStr, map in pairs(data.ballEnchantments) do
            if type(map) == "table" then
                for enchantId, lv in pairs(map) do
                    if enchantId ~= "gem_chance" then
                        local cur = gameState.idleEnchantments[enchantId] or 0
                        if lv > cur then
                            gameState.idleEnchantments[enchantId] = lv
                        end
                    end
                end
            end
        end
        print("[Save] Migrated per-ball enchantments to global format")
    end

    print("[Save] DeserializeIdle: level=" .. gameState.idleLevel
        .. " prestige=" .. gameState.idlePrestigeCount)
end

-- ============================================================================
-- 本地存储（同步）
-- ============================================================================

function M.SaveLocal()
    local data = M.Serialize()
    local ok, jsonStr = pcall(cjson.encode, data)
    if not ok then
        print("[Save] Local encode error: " .. tostring(jsonStr))
        return false
    end
    print(string.format("[Save] Data size: %.1f KB", #jsonStr / 1024))

    -- 签名信封：{ d = "原始JSON", s = "签名" }
    local sig = M.ComputeSignature(jsonStr)
    local envelope = { d = jsonStr, s = sig }
    local ok2, envStr = pcall(cjson.encode, envelope)
    if not ok2 then
        print("[Save] Envelope encode error: " .. tostring(envStr))
        return false
    end

    local file = File(SAVE_FILE, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(envStr)
        file:Close()
        return true
    end
    print("[Save] Local write failed")
    return false
end

function M.LoadLocal()
    if not fileSystem:FileExists(SAVE_FILE) then
        return nil
    end
    local file = File(SAVE_FILE, FILE_READ)
    if not file:IsOpen() then
        return nil
    end
    local content = file:ReadString()
    file:Close()
    local ok, outer = pcall(cjson.decode, content)
    if not ok or type(outer) ~= "table" then
        print("[Save] Local decode error")
        return nil
    end

    -- 新格式（有签名信封）
    if outer.d and outer.s then
        local expectedSig = M.ComputeSignature(outer.d)
        if outer.s ~= expectedSig then
            print("[Save] Signature mismatch! Save may be tampered.")
            -- 签名不匹配仍加载，但重置宝石为安全值
            local ok2, data = pcall(cjson.decode, outer.d)
            if ok2 and type(data) == "table" then
                data.gems = 0
                print("[Save] Gems reset due to tamper detection")
                return data
            end
            return nil
        end
        local ok2, data = pcall(cjson.decode, outer.d)
        if ok2 and type(data) == "table" then
            print("[Save] Local load OK (signed)")
            return data
        end
        return nil
    end

    -- 旧格式兼容（无签名，直接是存档数据）
    print("[Save] Local load OK (legacy unsigned)")
    return outer
end

-- ============================================================================
-- 云端存储（异步）
-- ============================================================================

function M.SaveCloud()
    -- WASM 保护：云端加载未成功前禁止写入，防止空数据覆盖
    if not cloudLoadSucceeded then
        print("[Save] Cloud save BLOCKED: cloud load not yet succeeded")
        return
    end
    -- 根据当前游戏阶段决定保存哪些 key
    local phase = gameState.gamePhase
    if phase == "idle" then
        M.SaveCloudKeys({ "shared", "idle" })
    elseif phase == "runes" then
        M.SaveCloudKeys({ "shared", "runes" })
    else
        -- playing / menu / 其他 → 保存主线
        M.SaveCloudKeys({ "shared", "main" })
    end
end

--- 按指定模块 key 保存到云端
---@param modules string[] 模块名数组，如 {"shared", "main"}
function M.SaveCloudKeys(modules)
    if not cloudLoadSucceeded then
        print("[Save] Cloud save BLOCKED: cloud load not yet succeeded")
        return
    end

    -- 构建要写入的 key-value 对
    local kvPairs = {}
    for _, mod in ipairs(modules) do
        local cloudKey = CLOUD_KEYS[mod]
        if cloudKey then
            local data
            if mod == "shared" then
                data = M.SerializeShared()
            elseif mod == "main" then
                data = M.SerializeMainGame()
            elseif mod == "runes" then
                data = M.SerializeRunes()
            elseif mod == "idle" then
                data = M.SerializeIdle()
            end
            if data then
                kvPairs[cloudKey] = data
            end
        end
    end

    -- 逐 key 写入（clientCloud:Set 单 key API）
    local pendingCount = 0
    local failCount = 0
    for k, _ in pairs(kvPairs) do pendingCount = pendingCount + 1 end
    if pendingCount == 0 then return end

    saveIndicator.status = "saving"
    saveIndicator.timer = 0

    for cloudKey, data in pairs(kvPairs) do
        clientCloud:Set(cloudKey, data, {
            ok = function()
                -- 刷新缓存
                local c = _getCache(cloudKey)
                c.data = data
                c.hasData = true
                c.timestamp = os.clock()

                pendingCount = pendingCount - 1
                if pendingCount <= 0 then
                    if failCount == 0 then
                        print("[Save] Cloud save OK (" .. table.concat(modules, ",") .. ")")
                        saveIndicator.status = "saved"
                    else
                        saveIndicator.status = "failed"
                    end
                    saveIndicator.timer = saveIndicator.fadeTime
                end
            end,
            error = function(code, reason)
                print("[Save] Cloud save error [" .. cloudKey .. "]: " .. tostring(reason))
                failCount = failCount + 1
                pendingCount = pendingCount - 1
                if pendingCount <= 0 then
                    saveIndicator.status = "failed"
                    saveIndicator.timer = saveIndicator.fadeTime
                end
            end,
        })
    end
end

--- 从云端读取存档（异步，回调返回 data 或 nil）
--- 保留兼容：读取旧版单 key（迁移用）
function M.LoadFromCloud(callback)
    clientCloud:Get(CLOUD_KEY_LEGACY, {
        ok = function(values, iscores)
            local data = values[CLOUD_KEY_LEGACY]
            if data and type(data) == "table" then
                print("[Save] Cloud load OK (legacy)")
                callback(data)
            else
                print("[Save] Cloud no save data (legacy)")
                callback(nil)
            end
        end,
        error = function(code, reason)
            print("[Save] Cloud load error (legacy): " .. tostring(reason))
            callback(nil)
        end,
    })
end

--- 轻量检查云端是否有存档（仅查询，不加载到游戏状态）
function M.CheckCloudSave(callback)
    -- 先检查新 key，再检查旧 key
    clientCloud:Get(CLOUD_KEYS.shared, {
        ok = function(values, iscores)
            local data = values[CLOUD_KEYS.shared]
            if data and type(data) == "table" then
                callback(true)
            else
                -- 新 key 无数据，回退检查旧 key
                clientCloud:Get(CLOUD_KEY_LEGACY, {
                    ok = function(vals2)
                        local d = vals2[CLOUD_KEY_LEGACY]
                        callback(d ~= nil and type(d) == "table")
                    end,
                    error = function()
                        callback(false)
                    end,
                })
            end
        end,
        error = function(code, reason)
            print("[Save] Cloud check error: " .. tostring(reason))
            callback(false)
        end,
    })
end

-- ============================================================================
-- WASM 云存档安全 API
-- ============================================================================

--- 标记云端加载已成功（允许后续写入云端）
--- 在确认收到云端响应（含"无存档"响应）后调用
function M.MarkCloudLoadSucceeded()
    cloudLoadSucceeded = true
    print("[Save] Cloud load marked as succeeded, cloud writes now allowed")
end

--- 查询云加载是否已成功
---@return boolean
function M.IsCloudLoadSucceeded()
    return cloudLoadSucceeded
end

--- 使云端数据缓存失效（云端写入后调用，确保下次读取拿到最新数据）
---@param key string|nil 指定 key 失效，nil 则全部失效
function M.InvalidateCloudCache(key)
    if key then
        local c = _cloudCache[key]
        if c then
            c.hasData = false
            c.data = nil
        end
    else
        _cloudCache = {}
    end
end

local CLOUD_LOAD_TIMEOUT = 25  -- 单次请求超时（秒），WASM 冷启动可能需要 15s+

--- 预热云连接（Start 时调用，火后即忘，成功则填充缓存）
--- 同时预热所有分 key 和旧版 key（迁移检测）
function M.PrefetchCloud()
    -- 预热所有新 key
    local allKeys = {}
    for _, cloudKey in pairs(CLOUD_KEYS) do
        allKeys[#allKeys + 1] = cloudKey
    end
    -- 同时预热旧版 key（迁移检测需要）
    allKeys[#allKeys + 1] = CLOUD_KEY_LEGACY

    print("[Save] Prefetch cloud started (" .. #allKeys .. " keys)")
    for _, cloudKey in ipairs(allKeys) do
        local cache = _getCache(cloudKey)
        if cache.hasData then
            -- 已有缓存，跳过
        else
            clientCloud:Get(cloudKey, {
                ok = function(values, iscores)
                    local c = _getCache(cloudKey)
                    if c.hasData then return end  -- 另一个加载已填充缓存
                    local data = values[cloudKey]
                    if data and type(data) == "table" then
                        c.data = data
                        c.hasData = true
                        c.timestamp = os.clock()
                        print("[Save] Prefetch OK [" .. cloudKey .. "], data cached")
                    else
                        c.data = nil
                        c.hasData = true
                        c.timestamp = os.clock()
                        print("[Save] Prefetch OK [" .. cloudKey .. "], no data")
                    end
                end,
                error = function(code, reason)
                    print("[Save] Prefetch error [" .. cloudKey .. "] (non-fatal): " .. tostring(reason))
                end,
            })
        end
    end
end

--- 迁移检测：新 key 无数据或数据明显不完整时，从旧版 save_data 恢复
--- 判断标准：
---   1. 新 key 全部为空（nil）
---   2. shared 存在但 saveCount <= 1（说明是刚被空数据覆盖的默认值）
---      且旧版 key 的 saveCount 更大
---@param result table<string, table|nil> 已加载的分 key 数据
---@param modules string[] 请求的模块名
function M._CheckAndApplyMigration(result, modules)
    local lc = _getCache(CLOUD_KEY_LEGACY)
    if not lc.hasData or not lc.data then
        return  -- 旧版 key 无数据，无法迁移
    end

    local legacyCount = lc.data.saveCount or 0
    if legacyCount <= 0 then
        return  -- 旧版也没有有效数据
    end

    -- 检查新 key 是否有可信数据
    local newCount = 0
    if result.shared and type(result.shared) == "table" then
        newCount = result.shared.saveCount or 0
    end

    local shouldMigrate = false
    if newCount <= 0 then
        -- 新 key 无有效数据
        shouldMigrate = true
    elseif legacyCount > newCount + 5 then
        -- 旧版 saveCount 远大于新版（说明新版可能是被空数据覆盖后的少量自动保存）
        shouldMigrate = true
        print(string.format("[Save] Legacy saveCount=%d >> new saveCount=%d, forcing migration",
            legacyCount, newCount))
    end

    if shouldMigrate then
        print(string.format("[Save] Migration triggered: legacy saveCount=%d, new saveCount=%d",
            legacyCount, newCount))
        for _, mod in ipairs(modules) do
            result[mod] = lc.data
        end
        result._migrated = true
    end
end

--- 按模块 key 加载云端数据（分 key 版本）
--- 优先从 prefetch 缓存读取，缓存 miss 时发起网络请求
--- 同时检测旧版 save_data key 用于迁移
---@param modules string[] 模块名数组，如 {"shared", "main"}
---@param callback fun(result: table<string,table|nil>, allFailed: boolean)
---   result: { shared = data|nil, main = data|nil, ... }
---   allFailed: true 表示超时/全部失败
function M.LoadCloudKeys(modules, callback)
    -- 收集需要加载的 cloud key
    local keysToLoad = {}   -- { {mod=modName, cloudKey=cloudKey}, ... }
    local result = {}       -- { modName = data|nil }
    local cacheHits = 0

    for _, mod in ipairs(modules) do
        local cloudKey = CLOUD_KEYS[mod]
        if cloudKey then
            local c = _getCache(cloudKey)
            if c.hasData and (os.clock() - c.timestamp) < CLOUD_CACHE_TTL then
                -- 缓存命中
                result[mod] = c.data
                cacheHits = cacheHits + 1
            else
                c.hasData = false
                keysToLoad[#keysToLoad + 1] = { mod = mod, cloudKey = cloudKey }
            end
        end
    end

    -- 同时加载旧版 key（迁移检测）
    local legacyNeeded = false
    local legacyCache = _getCache(CLOUD_KEY_LEGACY)
    if legacyCache.hasData and (os.clock() - legacyCache.timestamp) < CLOUD_CACHE_TTL then
        -- 已缓存，不需要额外请求
    else
        legacyCache.hasData = false
        legacyNeeded = true
    end

    local totalToFetch = #keysToLoad + (legacyNeeded and 1 or 0)

    -- 全部缓存命中
    if totalToFetch == 0 then
        -- 缓存命中时也要检查迁移：新 key 可能被 prefetch 缓存为"空"，
        -- 或者新 key 被意外写入了默认空数据
        M._CheckAndApplyMigration(result, modules)
        print(string.format("[Save] LoadCloudKeys all cache HIT (%d keys, migrated=%s)",
            cacheHits, tostring(result._migrated or false)))
        callback(result, false)
        return
    end

    -- 发起网络请求
    local pending = {
        responded = false,
        elapsed = 0,
        callback = callback,
        result = result,
        remaining = totalToFetch,
        failCount = 0,
        modules = modules,
    }
    M._pendingCloudLoad = pending

    print(string.format("[Save] LoadCloudKeys started: %d cached, %d to fetch (timeout=%ds)",
        cacheHits, totalToFetch, CLOUD_LOAD_TIMEOUT))

    local function onOneDone()
        pending.remaining = pending.remaining - 1
        if pending.remaining <= 0 then
            if pending.responded then return end
            pending.responded = true
            M._pendingCloudLoad = nil

            if pending.failCount >= totalToFetch then
                -- 全部失败
                print("[Save] LoadCloudKeys ALL FAILED")
                callback(pending.result, true)
            else
                M._CheckAndApplyMigration(pending.result, modules)
                callback(pending.result, false)
            end
        end
    end

    -- 请求各新 key
    for _, entry in ipairs(keysToLoad) do
        clientCloud:Get(entry.cloudKey, {
            ok = function(values)
                if pending.responded then return end
                local data = values[entry.cloudKey]
                local c = _getCache(entry.cloudKey)
                if data and type(data) == "table" then
                    c.data = data
                    c.hasData = true
                    c.timestamp = os.clock()
                    pending.result[entry.mod] = data
                    print("[Save] LoadCloudKeys OK [" .. entry.cloudKey .. "]")
                else
                    c.data = nil
                    c.hasData = true
                    c.timestamp = os.clock()
                    print("[Save] LoadCloudKeys empty [" .. entry.cloudKey .. "]")
                end
                onOneDone()
            end,
            error = function(code, reason)
                if pending.responded then return end
                print("[Save] LoadCloudKeys error [" .. entry.cloudKey .. "]: " .. tostring(reason))
                pending.failCount = pending.failCount + 1
                onOneDone()
            end,
        })
    end

    -- 请求旧版 key（迁移检测）
    if legacyNeeded then
        clientCloud:Get(CLOUD_KEY_LEGACY, {
            ok = function(values)
                if pending.responded then return end
                local data = values[CLOUD_KEY_LEGACY]
                local c = _getCache(CLOUD_KEY_LEGACY)
                if data and type(data) == "table" then
                    c.data = data
                    c.hasData = true
                    c.timestamp = os.clock()
                    print("[Save] LoadCloudKeys OK [legacy]")
                else
                    c.data = nil
                    c.hasData = true
                    c.timestamp = os.clock()
                    print("[Save] LoadCloudKeys empty [legacy]")
                end
                onOneDone()
            end,
            error = function(code, reason)
                if pending.responded then return end
                print("[Save] LoadCloudKeys error [legacy]: " .. tostring(reason))
                pending.failCount = pending.failCount + 1
                onOneDone()
            end,
        })
    else
        -- 旧版已缓存，不需要请求
    end
end

--- 迁移写入：将旧单 key 数据拆分写入新 key（后台执行，不阻塞）
function M.MigrateLegacyToSplitKeys()
    if not cloudLoadSucceeded then return end
    local lc = _getCache(CLOUD_KEY_LEGACY)
    if not lc.hasData or not lc.data then return end

    print("[Save] Migrating legacy save_data to split keys...")
    -- 用旧数据恢复 gameState，然后按新格式写入所有 key
    M.SaveCloudKeys({ "shared", "main", "runes", "idle" })
    print("[Save] Migration write issued for all 4 keys")
end

--- 兼容旧接口：单 key 加载（用于旧代码过渡期间）
--- @deprecated 请使用 LoadCloudKeys
---@param callback fun(data: table|nil, allFailed: boolean)
function M.LoadFromCloudSafe(callback)
    -- 包装为旧接口格式：返回旧版 legacy 数据
    local legacyCache = _getCache(CLOUD_KEY_LEGACY)
    if legacyCache.hasData and (os.clock() - legacyCache.timestamp) < CLOUD_CACHE_TTL then
        print("[Save] LoadFromCloudSafe cache HIT (legacy)")
        callback(legacyCache.data, false)
        return
    end

    local pending = { responded = false, elapsed = 0, callback = callback }
    M._pendingCloudLoad = pending

    print("[Save] LoadFromCloudSafe started (legacy, timeout=" .. CLOUD_LOAD_TIMEOUT .. "s)")
    clientCloud:Get(CLOUD_KEY_LEGACY, {
        ok = function(values)
            if pending.responded then return end
            pending.responded = true
            M._pendingCloudLoad = nil
            local data = values[CLOUD_KEY_LEGACY]
            local c = _getCache(CLOUD_KEY_LEGACY)
            if data and type(data) == "table" then
                c.data = data
                c.hasData = true
                c.timestamp = os.clock()
                callback(data, false)
            else
                c.data = nil
                c.hasData = true
                c.timestamp = os.clock()
                callback(nil, false)
            end
        end,
        error = function(code, reason)
            if pending.responded then return end
            pending.responded = true
            M._pendingCloudLoad = nil
            print("[Save] LoadFromCloudSafe error: " .. tostring(reason))
            callback(nil, true)
        end,
    })
end

--- 每帧调用：驱动云加载超时检测（在 HandleUpdate 中调用）
---@param dt number
function M.UpdateCloudLoadTimeout(dt)
    local p = M._pendingCloudLoad
    if not p or p.responded then return end
    p.elapsed = p.elapsed + dt
    if p.elapsed >= CLOUD_LOAD_TIMEOUT then
        p.responded = true
        M._pendingCloudLoad = nil
        print(string.format("[Save] Cloud load TIMEOUT after %.1fs", CLOUD_LOAD_TIMEOUT))
        p.callback(nil, true)
    end
end

-- ============================================================================
-- 统一保存接口
-- ============================================================================

--- 同步写本地 + 标记云端待写（30 秒普通节流）
function M.Save()
    M.SaveLocal()
    if not cloudDirty then
        cloudDirty = true
        cloudTimer = 0
    end
end

--- 更新保存状态指示器计时
local function UpdateSaveIndicator(dt)
    if saveIndicator.status == "saved" or saveIndicator.status == "failed" then
        saveIndicator.timer = saveIndicator.timer - dt
        if saveIndicator.timer <= 0 then
            saveIndicator.status = nil
            saveIndicator.timer = 0
        end
    end
end

--- 在 HandleUpdate 中调用，处理云端节流写入和排行榜对比
---@param dt number
function M.Update(dt)
    -- 保存状态指示器倒计时
    UpdateSaveIndicator(dt)

    -- 云端存档节流写入（两级：紧急 5s / 普通 30s）
    if cloudDirty then
        cloudTimer = cloudTimer + dt
        local threshold = cloudUrgent and CLOUD_THROTTLE_URGENT or CLOUD_THROTTLE_NORMAL
        if cloudTimer >= threshold then
            cloudTimer = 0
            cloudDirty = false
            cloudUrgent = false
            M.SaveCloud()
        end
    end

    -- 定时对比当前分数与最高分，超过则上传排行榜
    rankCheckTimer = rankCheckTimer + dt
    if rankCheckTimer >= RANK_CHECK_INTERVAL then
        rankCheckTimer = 0
        M.CheckAndUploadBest()
    end
end

--- 获取保存状态指示器数据（供 Renderer 读取）
--- @return string|nil status "saving"|"saved"|"failed"|nil
--- @return number alpha 0~1 淡出透明度
function M.GetSaveIndicator()
    local st = saveIndicator.status
    if not st then return nil, 0 end
    if st == "saving" then
        return st, 1.0
    end
    -- saved / failed: 淡出
    local alpha = math.min(1, saveIndicator.timer / saveIndicator.fadeTime)
    return st, alpha
end

--- 对比当前分数与最高分，超过则更新最高分并上传排行榜
function M.CheckAndUploadBest()
    local score = gameState.totalEarned
    local round = gameState.round
    if score > gameState.bestScore then
        gameState.bestScore = score
        gameState.bestRound = round
        M.Save()  -- 持久化最高分
        EventBus.emit("best_score_updated")
        print("[Save] New best score: " .. score .. " round: " .. round)
    end
end

--- 立即写入云端（广告奖励/手动保存）
function M.Flush()
    cloudDirty = false
    cloudUrgent = false
    cloudTimer = 0
    M.SaveCloud()
end

-- ============================================================================
-- 事件监听
-- ============================================================================

EventBus.on("save_trigger", function()
    M.Save()
end)

-- ============================================================================
-- 存档签名（SDBM hash）
-- ============================================================================

--- SDBM hash 算法（纯 Lua 实现，整数运算）
---@param s string
---@return integer
local function sdbmHash(s)
    local h = 0
    for i = 1, #s do
        local c = string.byte(s, i)
        h = c + (h << 6) + (h << 16) - h
        h = h & 0xFFFFFFFF  -- 保持 32 位
    end
    return h
end

--- 计算存档数据的签名
---@param jsonStr string 存档 JSON 字符串
---@return string 十六进制签名
function M.ComputeSignature(jsonStr)
    local raw = SIGN_SALT .. jsonStr .. SIGN_SALT
    local h = sdbmHash(raw)
    return string.format("%08x", h)
end

-- ============================================================================
-- 工具函数
-- ============================================================================

function M._CopyArray(arr)
    local copy = {}
    for i = 1, #arr do
        copy[i] = arr[i]
    end
    return copy
end

function M._CopyTable(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = v
    end
    return copy
end

function M._CopySlots(slots)
    local copy = {}
    for i, s in ipairs(slots) do
        copy[i] = { kind = s.kind, level = s.level }
    end
    return copy
end

--- 四舍五入到1位小数（瘦身用）
local function _round1(v)
    return math.floor(v * 10 + 0.5) / 10
end

--- 序列化场上的球（只保留可恢复的物理字段，跳过 trail 等渲染数据）
--- 瘦身：浮点数截断到1位小数，省略默认值字段
function M._SerializeBalls(balls)
    local out = {}
    for i = 1, #balls do
        local b = balls[i]
        if b.alive then
            local entry = {
                x = _round1(b.x), y = _round1(b.y),
                vx = _round1(b.vx), vy = _round1(b.vy),
                r = _round1(b.radius),          -- 缩短 key: radius → r
                t = b.typeIndex,                 -- 缩短 key: typeIndex → t
                v = BigNum.serialize(b.value),   -- 缩短 key: value → v
            }
            -- 仅在非默认值时保存（省略 0/false/相同值）
            if (b.pegHits or 0) > 0 then entry.ph = b.pegHits end
            if b.hasSplit then entry.sp = true end
            if (b.aliveTime or 0) > 0.5 then entry.at = _round1(b.aliveTime) end
            local br = b.baseRadius or b.radius
            if math.abs(br - b.radius) > 0.1 then entry.br = _round1(br) end
            out[#out + 1] = entry
        end
    end
    return out
end

--- 反序列化球数据（兼容新旧格式）
function M._DeserializeBalls(data)
    if not data then return {} end
    local balls = {}
    for i = 1, #data do
        local d = data[i]
        local radius = d.r or d.radius
        balls[#balls + 1] = {
            x = d.x, y = d.y,
            vx = d.vx, vy = d.vy,
            radius = radius,
            typeIndex = d.t or d.typeIndex,
            value = BigNum.deserialize(d.v or d.value),
            trail = {},
            alive = true,
            pegHits = d.ph or d.pegHits or 0,
            hasSplit = d.sp or d.hasSplit or false,
            aliveTime = d.at or d.aliveTime or 0,
            baseRadius = d.br or d.baseRadius or radius,
        }
    end
    return balls
end

--- 序列化钉子命中计时器（稀疏格式：只存非零值，key=索引）
--- 瘦身：绝大多数钉子 hitTimer=0，稀疏格式大幅缩减数据量
function M._SerializePegTimers(pegs)
    local out = {}
    local hasAny = false
    for i = 1, #pegs do
        local t = pegs[i].hitTimer
        if t and t > 0.01 then  -- 忽略接近 0 的值
            out[tostring(i)] = math.floor(t * 100 + 0.5) / 100  -- 精度截断到 0.01
            hasAny = true
        end
    end
    if not hasAny then return nil end  -- 全为零时不保存此字段
    return out
end

--- 序列化 idleLevelData（只保存当前关卡）
---@param levelData table
---@param currentLevel number 当前所在关卡
function M._SerializeLevelData(levelData, currentLevel)
    if not levelData then return {} end
    local ld = levelData[currentLevel]
    if not ld then return {} end

    local slots = ld.slots or {}
    local lvArr = {}
    local dropsMap = nil
    for i = 1, #slots do
        lvArr[i] = slots[i].level or 1
        local d = slots[i].drops or 0
        if d > 0 then
            if not dropsMap then dropsMap = {} end
            dropsMap[tostring(i)] = d
        end
    end
    local entry = { sl = lvArr }
    if dropsMap then entry.dr = dropsMap end
    local bd = ld.ballsDropped or 0
    if bd > 0 then entry.bd = bd end
    local lbc = BigNum.serialize(ld.levelBallCoins or BigNum.new(0))
    if lbc ~= "0" and lbc ~= 0 then entry.lbc = lbc end
    local bc = BigNum.serialize(ld.ballCoins or BigNum.new(0))
    if bc ~= "0" and bc ~= 0 then entry.bc = bc end

    return { [tostring(currentLevel)] = entry }
end

--- 反序列化 idleLevelData（兼容新旧格式）
function M._DeserializeLevelData(data)
    if not data then return {} end
    local out = {}
    for lvStr, ld in pairs(data) do
        local lv = tonumber(lvStr)
        if lv then
            local slots = {}
            if ld.sl then
                -- 新格式 v2: sl = [level数组], dr = {稀疏drops}
                local dropsMap = ld.dr or {}
                for i = 1, #ld.sl do
                    slots[i] = {
                        kind = "good",
                        level = ld.sl[i] or 1,
                        drops = dropsMap[tostring(i)] or 0,
                    }
                end
            elseif ld.slots then
                -- 旧格式: slots = [{kind, level, drops}, ...]
                for i = 1, #ld.slots do
                    slots[i] = {
                        kind = ld.slots[i].kind or "good",
                        level = ld.slots[i].level or 2,
                        drops = ld.slots[i].drops or 0,
                    }
                end
            end
            out[lv] = {
                slots = slots,
                ballsDropped = ld.bd or ld.ballsDropped or 0,
                levelBallCoins = BigNum.deserialize(ld.lbc or ld.levelBallCoins or 0),
                ballCoins = BigNum.deserialize(ld.bc or ld.ballCoins or 0),
            }
        end
    end
    return out
end

return M
