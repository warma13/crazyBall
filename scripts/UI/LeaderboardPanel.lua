-- ============================================================================
-- UI/LeaderboardPanel.lua - 排行榜弹窗面板
-- ============================================================================

local UI = require("urhox-libs/UI")
local State = require("State")
local Leaderboard = require("Leaderboard")

local P = {}

--- 创建单条排行数据行
local function CreateRankRow(entry)
    local rankColor
    if entry.rank == 1 then rankColor = { 255, 215, 0, 255 }
    elseif entry.rank == 2 then rankColor = { 200, 210, 225, 255 }
    elseif entry.rank == 3 then rankColor = { 205, 133, 63, 255 }
    else rankColor = { 160, 170, 200, 220 }
    end

    local nameColor = entry.isMe and { 120, 220, 255, 255 } or { 210, 220, 240, 240 }
    local displayName = (entry.nickname or "玩家")
    if entry.isMe then displayName = displayName .. " (我)" end
    if #displayName > 14 then
        displayName = string.sub(displayName, 1, 11) .. "..."
    end

    local roundText = entry.round and entry.round > 0 and tostring(entry.round) or "-"

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        padding = { 5, 6, 5, 6 },
        backgroundColor = entry.isMe and { 40, 60, 100, 120 } or { 0, 0, 0, 0 },
        borderRadius = 4,
        alignItems = "center",
        children = {
            UI.Label {
                text = tostring(entry.rank),
                fontSize = 16,
                fontColor = rankColor,
                width = 24,
                textAlign = "center",
            },
            UI.Label {
                text = displayName,
                fontSize = 15,
                fontColor = nameColor,
                flexGrow = 1,
                flexShrink = 1,
            },
            UI.Label {
                text = roundText,
                fontSize = 15,
                fontColor = { 180, 220, 255, 220 },
                marginLeft = 4,
                marginRight = 4,
                textAlign = "center",
            },
            UI.Label {
                text = State.FormatNumber(entry.totalScore),
                fontSize = 15,
                fontColor = { 255, 230, 140, 240 },
                width = 65,
                textAlign = "right",
            },
        }
    }
end

--- 创建排行榜弹窗面板（固定高度，中间可滚动）
---@param cb table 回调表 { PlayClickSfx, HideLeaderboardPanel, RefreshLeaderboardPanel }
---@return table UI 面板
function P.CreateLeaderboardPanel(cb)
    -- 中间滚动区域的内容
    local scrollContent = {}

    if Leaderboard.loading then
        table.insert(scrollContent, UI.Label {
            text = "加载中...",
            fontSize = 16,
            fontColor = { 160, 170, 200, 200 },
            textAlign = "center",
            marginTop = 30,
        })
    elseif #Leaderboard.rankList == 0 then
        table.insert(scrollContent, UI.Label {
            text = "暂无数据",
            fontSize = 16,
            fontColor = { 160, 170, 200, 200 },
            textAlign = "center",
            marginTop = 30,
        })
    else
        for _, entry in ipairs(Leaderboard.rankList) do
            table.insert(scrollContent, CreateRankRow(entry))
        end
        -- "加载更多"按钮
        if Leaderboard.hasMore then
            table.insert(scrollContent, UI.Panel {
                width = "100%",
                justifyContent = "center",
                alignItems = "center",
                marginTop = 6,
                marginBottom = 4,
                children = {
                    UI.Button {
                        text = "加载更多",
                        fontSize = 14,
                        width = 120,
                        height = 32,
                        variant = "ghost",
                        onClick = function()
                            Leaderboard.LoadMore(function()
                                cb.RefreshLeaderboardPanel()
                            end)
                        end,
                    }
                }
            })
        end
    end

    -- 底部固定区域
    local bottomChildren = {}

    -- 我的排名
    if Leaderboard.myRank then
        table.insert(bottomChildren, UI.Label {
            text = "我的排名: #" .. Leaderboard.myRank .. "  总收益: " .. State.FormatNumber(State.gameState.totalEarned),
            fontSize = 14,
            fontColor = { 120, 200, 255, 220 },
            textAlign = "center",
        })
    end

    -- 整体弹窗（居中覆盖，固定高度 60%）
    return UI.Panel {
        id = "lbOverlay",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 140 },
        pointerEvents = "auto",
        onClick = function()
            cb.PlayClickSfx()
            cb.HideLeaderboardPanel()
        end,
        children = {
            UI.Panel {
                width = "85%",
                height = "60%",
                backgroundColor = { 20, 25, 50, 245 },
                borderColor = { 80, 110, 180, 200 },
                borderWidth = 2, borderRadius = 12,
                padding = { 12, 14, 10, 14 },
                pointerEvents = "auto",
                onClick = function() end,  -- 阻止穿透到蒙层
                children = {
                    -- 右上角关闭 X
                    UI.Panel {
                        position = "absolute",
                        top = 6, right = 8,
                        width = 26, height = 26, borderRadius = 13,
                        backgroundColor = { 50, 55, 80, 200 },
                        justifyContent = "center", alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function()
                            cb.PlayClickSfx()
                            cb.HideLeaderboardPanel()
                        end,
                        children = {
                            UI.Label {
                                text = "×",
                                fontSize = 19,
                                fontColor = { 180, 190, 220, 240 },
                                textAlign = "center",
                            },
                        }
                    },
                    -- 顶部：标题 + 表头（固定）
                    UI.Label {
                        text = "排行榜",
                        fontSize = 21,
                        fontColor = { 255, 220, 80, 255 },
                        textAlign = "center",
                        marginBottom = 6,
                    },
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        padding = { 2, 6, 4, 6 },
                        borderColor = { 50, 60, 90, 150 },
                        borderWidth = { 0, 0, 1, 0 },
                        children = {
                            UI.Label { text = "#", fontSize = 13, fontColor = { 140, 150, 180, 180 }, width = 24, textAlign = "center" },
                            UI.Label { text = "玩家", fontSize = 13, fontColor = { 140, 150, 180, 180 }, flexGrow = 1 },
                            UI.Label { text = "轮次", fontSize = 13, fontColor = { 140, 150, 180, 180 }, marginLeft = 4, marginRight = 4, textAlign = "center" },
                            UI.Label { text = "总收益", fontSize = 13, fontColor = { 140, 150, 180, 180 }, width = 65, textAlign = "right" },
                        }
                    },
                    -- 中间：可滚动排行列表
                    UI.ScrollView {
                        id = "lbScroll",
                        width = "100%",
                        flexGrow = 1,
                        flexShrink = 1,
                        padding = { 4, 0, 4, 0 },
                        children = {
                            UI.Panel {
                                width = "100%",
                                gap = 2,
                                children = scrollContent,
                            }
                        },
                    },
                    -- 底部：我的排名 + 关闭按钮（固定）
                    UI.Panel {
                        width = "100%",
                        borderColor = { 50, 60, 90, 150 },
                        borderWidth = { 1, 0, 0, 0 },
                        paddingTop = 8,
                        marginTop = 4,
                        children = bottomChildren,
                    },
                }
            },
        }
    }
end

return P
