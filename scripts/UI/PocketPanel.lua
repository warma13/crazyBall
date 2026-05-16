-- ============================================================================
-- UI/PocketPanel.lua - 口袋升级面板
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local State = require("State")
local Slots = require("Slots")

local gameState = State.gameState

local P = {}

--- 创建口袋升级列表
---@param cb table 回调表
---@return table UI 面板
function P.CreatePocketUpgradeRow(cb)
    local items = {}
    for i = 1, #gameState.slots do
        table.insert(items, P.CreatePocketItem(cb, i))
    end
    return UI.Panel {
        id = "pocketList",
        width = "100%",
        gap = 5,
        children = items,
    }
end

--- 创建单个口袋升级项
---@param cb table 回调表 { PlayClickSfx, ADS_ENABLED }
---@param index number 口袋索引
---@return table UI 面板
function P.CreatePocketItem(cb, index)
    local slot = gameState.slots[index]
    local color = Slots.GetSlotColor(slot)
    local label = Slots.GetSlotLabel(slot)
    local level = Slots.GetSlotLevel(slot)
    local nextLevel = level + 1
    local nextMult = Config.GetSlotMult(nextLevel)
    local cost = Slots.GetSlotUpgradeCost(slot)

    local fmtMult = State.FormatNumber(Config.GetSlotMult(level))
    local fmtNext = State.FormatNumber(nextMult)
    local titleText = "#" .. index .. "  x" .. fmtMult .. " → x" .. fmtNext
    local actionText = State.FormatNumber(cost)
    local canAfford = gameState.coins >= cost

    local accentColor = canAfford
        and { color[1], color[2], color[3], 220 }
        or { color[1], color[2], color[3], 80 }

    -- 右侧按钮组
    local rightChildren = {}
    if cb.ADS_ENABLED and not canAfford then
        table.insert(rightChildren, UI.Panel {
            flexDirection = "row",
            padding = { 5, 3, 5, 3 },
            borderRadius = 5,
            alignItems = "center", gap = 3,
            backgroundColor = { 200, 60, 40, 240 },
            pointerEvents = "auto",
            onClick = function(self)
                cb.PlayClickSfx()
                Slots.AdUpgradeSlot(index)
            end,
            children = {
                UI.Panel {
                    width = 20, height = 20,
                    backgroundImage = "image/icon_ad.png",
                    backgroundSize = "contain",
                },
                UI.Label {
                    text = "广告",
                    fontSize = 12,
                    fontColor = { 255, 255, 255, 240 },
                },
            },
        })
    end
    table.insert(rightChildren, UI.Panel {
        padding = { 5, 3, 5, 3 },
        borderRadius = 5,
        backgroundColor = canAfford and { 60, 140, 80, 220 } or { 45, 55, 80, 220 },
        pointerEvents = "none",
        children = {
            UI.Label {
                text = actionText,
                fontSize = 13,
                fontColor = canAfford
                    and { 180, 255, 180, 255 }
                    or { color[1], color[2], color[3], 150 },
                textAlign = "center",
            },
        }
    })

    return UI.Panel {
        id = "pocket_" .. index,
        width = "100%",
        flexDirection = "row",
        padding = { 6, 6, 6, 8 },
        backgroundColor = { 30, 35, 55, 200 },
        borderColor = accentColor,
        borderWidth = canAfford and 1.5 or 1, borderRadius = 8,
        alignItems = "center", gap = 8,
        pointerEvents = "auto",
        onClick = function()
            cb.PlayClickSfx()
            Slots.UpgradeSlot(index)
        end,
        children = {
            UI.Panel {
                minWidth = 24, height = 24, borderRadius = 5,
                paddingLeft = 4, paddingRight = 4,
                backgroundColor = { color[1], color[2], color[3], 180 },
                justifyContent = "center", alignItems = "center",
                pointerEvents = "none",
                children = {
                    UI.Label {
                        text = "x" .. fmtMult,
                        fontSize = 13,
                        fontColor = { 255, 255, 255, 240 },
                        textAlign = "center",
                    },
                }
            },
            UI.Label {
                flexGrow = 1,
                text = titleText,
                fontSize = 15,
                fontColor = { 200, 210, 230, 240 },
                pointerEvents = "none",
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center", gap = 4,
                children = rightChildren,
            },
        }
    }
end

return P
