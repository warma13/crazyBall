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
local CLOUD_KEY = "save_data"
local SAVE_VERSION = 4  -- 当前存档版本号（v4: 放置模式字段）
local SIGN_SALT = "cRz7$pBm!2xQ"  -- 签名盐值
local CLOUD_THROTTLE = 10  -- 云端写入最小间隔（秒）
local RANK_CHECK_INTERVAL = 15  -- 排行榜对比间隔（秒）

local cloudDirty = false
local cloudTimer = 0
local rankCheckTimer = 0

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
    return {
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
        idleBallAbilityLevels = M._CopyTable(gameState.idleBallAbilityLevels),
        idleUpgradeLevels = M._CopyTable(gameState.idleUpgradeLevels),
        idleSkills = M._CopyTable(gameState.idleSkills),
        idleSkillPickCount = gameState.idleSkillPickCount,

        -- 关卡系统
        idleLevel = gameState.idleLevel,
        idleMaxUnlockedLevel = gameState.idleMaxUnlockedLevel,
        idleBallsDropped = gameState.idleBallsDropped,
        idleBallCoins = BigNum.serialize(gameState.idleBallCoins),
        idleTotalBallCoins = BigNum.serialize(gameState.idleTotalBallCoins),
        idleGlobalBallValueBonus = gameState.idleGlobalBallValueBonus,
        idleGlobalSlotMultBonus = gameState.idleGlobalSlotMultBonus,
        idleLevelData = M._SerializeLevelData(gameState.idleLevelData),

        -- 附魔系统（{ [ballIndex] = { [enchantId] = level } }）
        ballEnchantments = M._SerializeEnchantments(gameState.ballEnchantments),

        -- 免广券
        adFreeTickets = gameState.adFreeTickets or 0,

        -- 局内状态（支持中途保存恢复）
        roundTimeLeft = gameState.roundTimeLeft,
        roundEarned = BigNum.serialize(gameState.roundEarned),
        roundTarget = BigNum.serialize(gameState.roundTarget),
        roundPhase = gameState.roundPhase,
        comboCount = gameState.comboCount,
        comboTimer = gameState.comboTimer,

        -- 场上球状态
        balls = M._SerializeBalls(gameState.balls),
        -- 钉子命中状态（仅保存 hitTimer 数组，位置由布局计算）
        pegHitTimers = M._SerializePegTimers(gameState.pegs),
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

    -- 附魔系统恢复
    if data.ballEnchantments then
        gameState.ballEnchantments = M._DeserializeEnchantments(data.ballEnchantments)
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
    if uid and AD_FREE_USERS[uid] then
        local grant = AD_FREE_USERS[uid]
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
-- 本地存储（同步）
-- ============================================================================

function M.SaveLocal()
    local data = M.Serialize()
    local ok, jsonStr = pcall(cjson.encode, data)
    if not ok then
        print("[Save] Local encode error: " .. tostring(jsonStr))
        return false
    end

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
    local data = M.Serialize()
    clientCloud:Set(CLOUD_KEY, data, {
        ok = function()
            print("[Save] Cloud save OK")
        end,
        error = function(code, reason)
            print("[Save] Cloud save error: " .. tostring(reason))
        end,
    })
end

--- 从云端读取存档（异步，回调返回 data 或 nil）
function M.LoadFromCloud(callback)
    clientCloud:Get(CLOUD_KEY, {
        ok = function(values, iscores)
            local data = values[CLOUD_KEY]
            if data and type(data) == "table" then
                print("[Save] Cloud load OK")
                callback(data)
            else
                print("[Save] Cloud no save data")
                callback(nil)
            end
        end,
        error = function(code, reason)
            print("[Save] Cloud load error: " .. tostring(reason))
            callback(nil)
        end,
    })
end

--- 轻量检查云端是否有存档（仅查询，不加载到游戏状态）
function M.CheckCloudSave(callback)
    clientCloud:Get(CLOUD_KEY, {
        ok = function(values, iscores)
            local data = values[CLOUD_KEY]
            callback(data ~= nil and type(data) == "table")
        end,
        error = function(code, reason)
            print("[Save] Cloud check error: " .. tostring(reason))
            callback(false)
        end,
    })
end

-- ============================================================================
-- 统一保存接口
-- ============================================================================

--- 同步写本地 + 标记云端待写
function M.Save()
    M.SaveLocal()
    cloudDirty = true
end

--- 在 HandleUpdate 中调用，处理云端节流写入和排行榜对比
---@param dt number
function M.Update(dt)
    -- 云端存档节流写入
    if cloudDirty then
        cloudTimer = cloudTimer + dt
        if cloudTimer >= CLOUD_THROTTLE then
            cloudTimer = 0
            cloudDirty = false
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

--- 立即刷入云端（退出前调用）
function M.Flush()
    if cloudDirty then
        cloudDirty = false
        cloudTimer = 0
        M.SaveCloud()
    end
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

--- 序列化场上的球（只保留可恢复的物理字段，跳过 trail 等渲染数据）
function M._SerializeBalls(balls)
    local out = {}
    for i = 1, #balls do
        local b = balls[i]
        if b.alive then
            out[#out + 1] = {
                x = b.x, y = b.y,
                vx = b.vx, vy = b.vy,
                radius = b.radius,
                typeIndex = b.typeIndex,
                value = BigNum.serialize(b.value),
                pegHits = b.pegHits or 0,
                hasSplit = b.hasSplit or false,
                aliveTime = b.aliveTime or 0,
                baseRadius = b.baseRadius or b.radius,
            }
        end
    end
    return out
end

--- 反序列化球数据
function M._DeserializeBalls(data)
    if not data then return {} end
    local balls = {}
    for i = 1, #data do
        local d = data[i]
        balls[#balls + 1] = {
            x = d.x, y = d.y,
            vx = d.vx, vy = d.vy,
            radius = d.radius,
            typeIndex = d.typeIndex,
            value = BigNum.deserialize(d.value),
            trail = {},
            alive = true,
            pegHits = d.pegHits or 0,
            hasSplit = d.hasSplit or false,
            aliveTime = d.aliveTime or 0,
            baseRadius = d.baseRadius or d.radius,
        }
    end
    return balls
end

--- 序列化钉子命中计时器（紧凑数组，只存 hitTimer）
function M._SerializePegTimers(pegs)
    local out = {}
    for i = 1, #pegs do
        out[i] = pegs[i].hitTimer or 0
    end
    return out
end

--- 序列化 idleLevelData（每关独立数据，含 ballCoins）
function M._SerializeLevelData(levelData)
    if not levelData then return {} end
    local out = {}
    for lv, ld in pairs(levelData) do
        out[tostring(lv)] = {
            slots = M._CopySlots(ld.slots or {}),
            ballsDropped = ld.ballsDropped or 0,
            levelBallCoins = BigNum.serialize(ld.levelBallCoins or BigNum.new(0)),
            ballCoins = BigNum.serialize(ld.ballCoins or BigNum.new(0)),
        }
    end
    return out
end

--- 反序列化 idleLevelData
function M._DeserializeLevelData(data)
    if not data then return {} end
    local out = {}
    for lvStr, ld in pairs(data) do
        local lv = tonumber(lvStr)
        if lv then
            local slots = {}
            if ld.slots then
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
                ballsDropped = ld.ballsDropped or 0,
                levelBallCoins = BigNum.deserialize(ld.levelBallCoins or 0),
                ballCoins = BigNum.deserialize(ld.ballCoins or 0),
            }
        end
    end
    return out
end

--- 序列化附魔 { [ballIndex] = { [enchantId] = level } } → JSON 友好格式
function M._SerializeEnchantments(enchantments)
    if not enchantments then return {} end
    local out = {}
    for ballIdx, map in pairs(enchantments) do
        if type(map) == "table" then
            out[tostring(ballIdx)] = M._CopyTable(map)
        end
    end
    return out
end

--- 反序列化附魔（JSON 的数字 key 会变成字符串，需恢复）
function M._DeserializeEnchantments(data)
    if not data then return {} end
    local out = {}
    for ballIdxStr, map in pairs(data) do
        local ballIdx = tonumber(ballIdxStr)
        if ballIdx and type(map) == "table" then
            out[ballIdx] = M._CopyTable(map)
        end
    end
    return out
end

return M
