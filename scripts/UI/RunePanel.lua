-- ============================================================================
-- UI/RunePanel.lua - 符文升级面板（TabBar 内嵌）
-- ============================================================================

local UI = require("urhox-libs/UI")
local State = require("State")
local Runes = require("Runes")

local gameState = State.gameState

local P = {}

--- 创建符文升级列表
---@param cb table 回调表 { PlayClickSfx }
---@return table UI 面板
function P.CreateRuneUpgradeRow(cb)
    local cards = {}

    -- 精粹余额 + 重新开始按钮
    local essenceCount = gameState.runeEssence or 0
    local MIN_ROUND = 10
    local canRestart = gameState.round > MIN_ROUND
    local previewReward = canRestart and Runes.PreviewEssenceReward(gameState.round - 1) or 0

    local restartBtn
    if canRestart then
        restartBtn = UI.Panel {
            flexDirection = "row",
            padding = { 5, 4, 5, 4 },
            borderRadius = 6,
            alignItems = "center",
            gap = 3,
            backgroundColor = { 180, 60, 60, 200 },
            borderColor = { 255, 100, 100, 120 },
            borderWidth = 1,
            pointerEvents = "auto",
            onClick = function()
                cb.PlayClickSfx()
                cb.ShowRuneRestartConfirm()
            end,
            children = {
                UI.Label {
                    text = string.format("重新开始 +%d", previewReward),
                    fontSize = 11,
                    fontColor = { 255, 220, 220, 255 },
                },
            },
        }
    else
        restartBtn = UI.Label {
            text = string.format("第%d轮后可重置", MIN_ROUND),
            fontSize = 11,
            fontColor = { 100, 90, 130, 140 },
        }
    end

    table.insert(cards, UI.Panel {
        width = "100%",
        flexDirection = "row",
        padding = { 8, 6, 8, 6 },
        alignItems = "center",
        justifyContent = "center",
        gap = 10,
        children = {
            UI.Label {
                text = string.format("符文精粹: %d", essenceCount),
                fontSize = 14,
                fontColor = { 180, 140, 255, 220 },
            },
            restartBtn,
        }
    })

    for _, rune in ipairs(Runes.RUNE_DEFS) do
        table.insert(cards, P.CreateRuneCard(cb, rune))
    end

    -- 底部提示
    table.insert(cards, UI.Panel {
        width = "100%",
        padding = { 6, 8, 6, 8 },
        alignItems = "center",
        children = {
            UI.Label {
                text = "闯关失败时根据到达轮次获得符文精粹",
                fontSize = 11,
                fontColor = { 120, 110, 160, 140 },
                textAlign = "center",
            },
        }
    })

    return UI.Panel {
        id = "runeList",
        width = "100%",
        gap = 5,
        children = cards,
    }
end

--- 创建单个符文卡片
---@param cb table 回调表
---@param rune table 符文配置
---@return table UI 面板
function P.CreateRuneCard(cb, rune)
    local level = Runes.GetRuneLevel(rune.id)
    local value = Runes.GetRuneValue(rune.id)
    local cost = Runes.GetUpgradeCost(rune.id)
    local essenceCount = gameState.runeEssence or 0
    local canAfford = essenceCount >= cost
    local rc = rune.color

    local desc = rune.descFunc(level, value)
    local costStr = tostring(cost)

    local borderColor = canAfford
        and { rc[1], rc[2], rc[3], 200 }
        or { rc[1], rc[2], rc[3], 80 }

    local bgColor = canAfford
        and { rc[1], rc[2], rc[3], 30 }
        or { 30, 35, 55, 200 }

    -- 升级按钮颜色
    local btnBg = canAfford
        and { rc[1], rc[2], rc[3], 200 }
        or { 40, 35, 60, 200 }
    local btnBorder = canAfford
        and { 255, 255, 255, 80 }
        or { 80, 70, 110, 120 }
    local btnTextColor = canAfford
        and { 255, 255, 255, 255 }
        or { 120, 110, 150, 160 }

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        padding = { 8, 10, 8, 10 },
        backgroundColor = bgColor,
        borderColor = borderColor,
        borderWidth = 1.5,
        borderRadius = 10,
        alignItems = "center",
        gap = 8,
        children = {
            -- 左侧：名称 + 描述
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                gap = 3,
                children = {
                    UI.Label {
                        text = rune.name .. "  Lv." .. level,
                        fontSize = 14,
                        fontColor = { rc[1], rc[2], rc[3], 255 },
                    },
                    UI.Label {
                        text = desc,
                        fontSize = 11,
                        fontColor = { 170, 170, 200, 200 },
                    },
                },
            },
            -- 右侧：升级按钮
            UI.Panel {
                flexDirection = "row",
                padding = { 6, 4, 6, 4 },
                borderRadius = 6,
                alignItems = "center",
                gap = 3,
                backgroundColor = btnBg,
                borderColor = btnBorder,
                borderWidth = 1,
                pointerEvents = "auto",
                onClick = function()
                    cb.PlayClickSfx()
                    if Runes.UpgradeRune(rune.id) then
                        -- 刷新由 EventBus "rune_upgraded" 触发
                    end
                end,
                children = {
                    UI.Label {
                        text = costStr,
                        fontSize = 12,
                        fontColor = btnTextColor,
                    },
                },
            },
        },
    }
end

return P
