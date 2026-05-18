-- ============================================================================
-- UI/IdlePrestigePanel.lua - 放置模式转生面板
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local BigNum = require("BigNum")
local State = require("State")

local gameState = State.gameState

local P = {}

--- 创建转生面板
---@param cb table 回调表 { PlayClickSfx, DoPrestige, CanPrestige }
---@return table UI 面板
function P.CreatePrestigePanel(cb)
    local canPrestige = cb.CanPrestige()
    local threshold = BigNum.new(Config.IDLE.PRESTIGE_THRESHOLD)

    return UI.Panel {
        id = "idlePrestigePanel",
        width = "100%",
        gap = 6,
        alignItems = "center",
        padding = { 6, 16, 6, 16 },
        children = {
            -- 标题
            UI.Label {
                text = "转生系统",
                fontSize = 18,
                fontColor = { 200, 160, 255, 255 },
                fontWeight = "bold",
                marginBottom = 8,
            },
            -- 分隔线
            UI.Panel {
                width = "100%", height = 1,
                backgroundColor = { 80, 60, 160, 100 },
                marginBottom = 10,
            },
            -- 信息行
            P._InfoRow("转生次数", tostring(gameState.idlePrestigeCount)),
            P._InfoRow("永久倍率", string.format("x%.1f", gameState.idlePrestigeMult)),
            P._InfoRow("累计收益", State.FormatNumber(gameState.idleTotalEarned)),
            P._InfoRow("转生门槛", State.FormatNumber(threshold)),
            -- 间距
            UI.Panel { width = "100%", height = 12 },
            -- 说明文字
            UI.Label {
                text = "转生将重置所有放置模式进度",
                fontSize = 12,
                fontColor = { 160, 170, 200, 180 },
                textAlign = "center",
            },
            UI.Label {
                text = string.format("但永久获得 +%.0f%% 收益加成", Config.IDLE.PRESTIGE_MULT_BONUS * 100),
                fontSize = 12,
                fontColor = { 160, 170, 200, 180 },
                textAlign = "center",
                marginBottom = 16,
            },
            -- 转生按钮
            UI.Panel {
                width = "80%",
                padding = { 14, 12, 14, 12 },
                borderRadius = 12,
                backgroundColor = canPrestige
                    and { 120, 60, 200, 240 }
                    or { 50, 50, 65, 180 },
                borderColor = canPrestige
                    and { 180, 120, 255, 200 }
                    or { 80, 80, 100, 120 },
                borderWidth = 2,
                justifyContent = "center", alignItems = "center",
                pointerEvents = "auto",
                onClick = function()
                    if canPrestige then
                        cb.PlayClickSfx()
                        cb.DoPrestige()
                    end
                end,
                children = {
                    UI.Label {
                        text = "转生",
                        fontSize = 20,
                        fontColor = canPrestige
                            and { 255, 255, 255, 255 }
                            or { 120, 120, 140, 150 },
                        fontWeight = "bold",
                        textAlign = "center",
                    },
                },
            },
        },
    }
end

--- 信息行辅助函数
---@param label string
---@param value string
---@return table UI 面板
function P._InfoRow(label, value)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        padding = { 4, 6, 4, 6 },
        children = {
            UI.Label {
                text = label,
                fontSize = 14,
                fontColor = { 160, 170, 200, 220 },
            },
            UI.Label {
                text = value,
                fontSize = 14,
                fontColor = { 220, 220, 240, 240 },
                fontWeight = "bold",
            },
        },
    }
end

return P
