-- ============================================================================
-- UI/FailedPanel.lua - 失败弹窗面板
-- ============================================================================

local UI = require("urhox-libs/UI")
local State = require("State")
local BigNum = require("BigNum")

local P = {}

--- 创建失败弹窗面板
---@param cb table 回调表 { PlayClickSfx, ADS_ENABLED, HideFailedPanel, OnFailedRestart }
---@param info table { round, coins, gems, pct }
---@return table UI 面板
function P.CreateFailedPanel(cb, info)
    local carryCoins = BigNum.floor(info.coins * 0.2)
    local carryGems = math.floor(info.gems * 0.2)

    return UI.Panel {
        id = "failedOverlay",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = "85%",
                backgroundColor = { 25, 30, 55, 250 },
                borderColor = { 255, 80, 80, 180 },
                borderWidth = 2, borderRadius = 14,
                padding = { 20, 22, 16, 22 },
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function() end,
                children = {
                    -- 标题
                    UI.Label {
                        text = "时间到",
                        fontSize = 24,
                        fontColor = { 255, 100, 100, 255 },
                        fontWeight = "bold",
                    },
                    -- 轮次与完成度
                    UI.Label {
                        text = "第 " .. info.round .. " 轮  完成 " .. info.pct .. "%",
                        fontSize = 14,
                        fontColor = { 180, 190, 220, 200 },
                        marginTop = 6,
                    },
                    -- 分割线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 90, 130, 100 },
                        marginTop = 14, marginBottom = 14,
                    },
                    -- 广告选项说明
                    UI.Label {
                        text = "观看广告可携带 20% 资源重新开始",
                        fontSize = 13,
                        fontColor = { 200, 210, 240, 200 },
                    },
                    -- 携带资源预览
                    UI.Panel {
                        flexDirection = "row",
                        gap = 20,
                        marginTop = 8, marginBottom = 16,
                        justifyContent = "center",
                        children = {
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 4,
                                children = {
                                    UI.Label { text = "💰", fontSize = 16 },
                                    UI.Label {
                                        text = State.FormatNumber(carryCoins),
                                        fontSize = 15,
                                        fontColor = { 255, 220, 80, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 4,
                                children = {
                                    UI.Label { text = "💎", fontSize = 16 },
                                    UI.Label {
                                        text = tostring(carryGems),
                                        fontSize = 15,
                                        fontColor = { 100, 200, 255, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            },
                        },
                    },
                    -- 看广告按钮
                    cb.ADS_ENABLED and UI.Panel {
                        width = "100%",
                        padding = { 13, 12, 13, 12 },
                        backgroundColor = { 220, 140, 30, 240 },
                        borderRadius = 10,
                        justifyContent = "center", alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function()
                            cb.PlayClickSfx()
                            cb.HideFailedPanel()
                            cb.OnFailedRestart(true, carryCoins, carryGems)
                        end,
                        children = {
                            UI.Label {
                                text = "▶ 观看广告，携带资源",
                                fontSize = 16,
                                fontColor = { 255, 255, 255, 255 },
                                fontWeight = "bold",
                            },
                        },
                    } or nil,
                    -- 直接重开按钮
                    UI.Panel {
                        width = "100%",
                        padding = { 11, 10, 11, 10 },
                        backgroundColor = { 50, 55, 80, 220 },
                        borderColor = { 80, 90, 120, 150 },
                        borderWidth = 1, borderRadius = 10,
                        justifyContent = "center", alignItems = "center",
                        marginTop = 8,
                        pointerEvents = "auto",
                        onClick = function()
                            cb.PlayClickSfx()
                            cb.HideFailedPanel()
                            cb.OnFailedRestart(false, nil, nil)
                        end,
                        children = {
                            UI.Label {
                                text = "直接重新开始",
                                fontSize = 14,
                                fontColor = { 160, 170, 200, 220 },
                            },
                        },
                    },
                },
            },
        },
    }
end

return P
