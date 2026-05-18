-- ============================================================================
-- Leaderboard.lua - 排行榜模块（log10 整数编码存储）
-- ============================================================================
-- bestScore 使用 BigNum，可达天文数字。
-- 存储方案：score_log = floor(log10(bestScore) * 1e6)
--   保序（log10 单调递增），int32 可容纳 log10 值到 ~2147（即 10^2147）
--   展示时用 BigNum.fromLog10(score_log / 1e6) 还原为可读格式。
-- 只记录历史最高分，不会被低分覆盖。
-- ============================================================================

local State = require("State")
local BigNum = require("BigNum")
local EventBus = require("EventBus")

local M = {}

local LOG_PRECISION = 1000000  -- log10 值乘以 1e6 转为整数
local PAGE_SIZE = 10            -- 每页加载条数
local LOADING_TIMEOUT = 8      -- loading 超时（秒），防止卡死

-- 排行榜缓存
M.rankList = {}             -- { {rank, userId, nickname, totalScore(BigNum), round}, ... }
M.myRank = nil              -- 我的排名（数字或nil=未上榜）
M.myScore = nil             -- 我的分数（BigNum）
M.loading = false           -- 正在加载中
M.loadingTimer = 0          -- loading 计时器
M.hasMore = true            -- 是否还有更多数据可加载
M.bestUploadedLog = -1      -- 已上传的最高 log10 整数值（只上传更高分）

--- 初始化：强制上传一次当前 bestScore（完成 score_log 迁移）
--- bestUploadedLog 保持 -1，让 UploadScore 一定能通过 > 检查并上传
function M.Init()
    local bestBN = State.gameState.bestScore
    local log10val = BigNum.toLog10(bestBN)
    if log10val > 0 then
        print("[Leaderboard] Init: force migration upload, log10=" .. log10val)
        M.UploadScore()  -- bestUploadedLog == -1，一定会上传
    else
        print("[Leaderboard] Init: no score to upload")
    end
end

--- 将 bestScore 编码为 log10 整数并上传（仅当超过已上传最高分时）
function M.UploadScore()
    local bestBN = State.gameState.bestScore
    local log10val = BigNum.toLog10(bestBN)
    if log10val <= 0 then return end
    local logInt = math.floor(log10val * LOG_PRECISION)
    local round = State.gameState.bestRound
    -- 只在超过已上传最高分时上传
    if logInt <= M.bestUploadedLog then return end
    M.bestUploadedLog = logInt

    clientCloud:BatchSet()
        :SetInt("score_log", logInt)
        :SetInt("max_round", round)
        :Save("排行榜分数", {
            ok = function()
                print("[Leaderboard] Upload OK: score_log=" .. logInt .. " round=" .. round)
            end,
            error = function(code, reason)
                print("[Leaderboard] Upload error: " .. tostring(reason))
                M.bestUploadedLog = -1  -- 失败时允许重试
            end
        })
end

--- 从排行榜 item 还原为 BigNum 分数
local function ReconstructScore(item)
    local logInt = (item.iscore and item.iscore.score_log) or 0
    if logInt <= 0 then
        -- 兼容旧版 score_high/score_low 格式
        local high = (item.iscore and item.iscore.score_high) or 0
        local low = (item.iscore and item.iscore.score_low) or 0
        if high > 0 or low > 0 then
            return BigNum.new(high * 1000000000 + low)
        end
        return BigNum.new(0)
    end
    return BigNum.fromLog10(logInt / LOG_PRECISION)
end

--- 内部：从指定偏移拉取一页数据并解析
---@param startIndex number 起始偏移（0-based）
---@param isAppend boolean 是否追加到现有列表（true=加载更多，false=刷新）
---@param callback function|nil 完成回调
local function FetchPage(startIndex, isAppend, callback)
    clientCloud:GetRankList("score_log", startIndex, PAGE_SIZE, {
        ok = function(rankList)
            local entries = {}
            local userIds = {}

            for i, item in ipairs(rankList) do
                local total = ReconstructScore(item)
                local round = (item.iscore and item.iscore.max_round) or 0
                table.insert(entries, {
                    rank = startIndex + i,
                    userId = item.userId,
                    nickname = nil,
                    totalScore = total,
                    round = round,
                    isMe = (item.userId == clientCloud.userId),
                })
                table.insert(userIds, item.userId)
            end

            -- 判断是否还有更多
            M.hasMore = (#rankList >= PAGE_SIZE)

            local function finalize(entryList)
                if isAppend then
                    for _, e in ipairs(entryList) do
                        table.insert(M.rankList, e)
                    end
                else
                    M.rankList = entryList
                end
                M.loading = false
                if callback then callback(M.rankList) end
            end

            if #userIds == 0 then
                finalize(entries)
                return
            end

            -- 查询昵称
            GetUserNickname({
                userIds = userIds,
                onSuccess = function(nicknames)
                    local map = {}
                    for _, info in ipairs(nicknames) do
                        map[info.userId] = info.nickname or ""
                    end
                    for _, entry in ipairs(entries) do
                        entry.nickname = map[entry.userId] or "玩家"
                    end
                    finalize(entries)
                end,
                onError = function(errorCode)
                    for _, entry in ipairs(entries) do
                        entry.nickname = "玩家"
                    end
                    finalize(entries)
                end,
            })
        end,
        error = function(code, reason)
            print("[Leaderboard] Fetch error: " .. tostring(reason))
            M.loading = false
            if callback then callback(nil) end
        end,
    }, "max_round", "score_high", "score_low")
end

--- 拉取排行榜（首页）+ 查询昵称
function M.FetchRankList(callback)
    -- 超时保护：如果上次 loading 卡死，强制重置
    if M.loading and M.loadingTimer >= LOADING_TIMEOUT then
        print("[Leaderboard] Loading timeout, force reset")
        M.loading = false
    end
    if M.loading then return end
    M.loading = true
    M.loadingTimer = 0
    M.hasMore = true

    FetchPage(0, false, callback)

    -- 同时查询自己的排名
    clientCloud:GetUserRank(clientCloud.userId, "score_log", {
        ok = function(rank, scoreValue)
            M.myRank = rank
            M.myScore = State.gameState.bestScore
        end,
        error = function() end,
    })
end

--- 加载更多（下一页）
function M.LoadMore(callback)
    if M.loading or not M.hasMore then return end
    M.loading = true
    M.loadingTimer = 0

    FetchPage(#M.rankList, true, callback)
end

--- 在 HandleUpdate 中调用，处理 loading 超时计时
---@param dt number
function M.Update(dt)
    if M.loading then
        M.loadingTimer = M.loadingTimer + dt
    end
end

-- 最高分更新时上传排行榜
EventBus.on("best_score_updated", function()
    M.UploadScore()
end)

return M
