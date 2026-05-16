-- ============================================================================
-- UI/SkinPanel.lua - 球皮肤选择弹窗
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local State = require("State")

local gameState = State.gameState

local P = {}

--- 广告解锁皮肤
---@param cb table 回调表
---@param ballIndex number 球索引
---@param skinId string 皮肤 ID
function P.AdUnlockSkin(cb, ballIndex, skinId)
    ---@diagnostic disable-next-line: undefined-global
    local sdk = sdk
    gameState.paused = true
    if not sdk then
        gameState.paused = false
        -- SDK 不可用时直接解锁
        local skinKey = ballIndex .. "_" .. skinId
        gameState.unlockedSkins[skinKey] = true
        gameState.ballSkins[ballIndex] = skinId
        State.uiDirty = true
        cb.ShowSkinPanel(ballIndex)
        cb.RefreshBallItem(ballIndex)
        if ballIndex == gameState.selectedBallType then
            cb.UpdateDropButton()
        end
        local SaveSystem = require("SaveSystem")
        SaveSystem.Save()
        return
    end
    sdk:ShowRewardVideoAd(function(result)
        gameState.paused = false
        if result.success then
            local skinKey = ballIndex .. "_" .. skinId
            gameState.unlockedSkins[skinKey] = true
            gameState.ballSkins[ballIndex] = skinId
            State.uiDirty = true
            cb.ShowSkinPanel(ballIndex)
            cb.RefreshBallItem(ballIndex)
            if ballIndex == gameState.selectedBallType then
                cb.UpdateDropButton()
            end
            -- 自动保存
            local SaveSystem = require("SaveSystem")
            SaveSystem.Save()
        end
    end)
end

--- 创建球皮肤选择面板
---@param cb table 回调表 { PlayClickSfx, ShowSkinPanel, HideSkinPanel, RefreshBallItem, UpdateDropButton }
---@param ballIndex number 球索引
---@return table UI 面板
function P.CreateSkinPanel(cb, ballIndex)
    local bt = Config.BALL_TYPES[ballIndex]
    if not bt then return UI.Panel {} end

    local skins = Config.GetBallSkins(ballIndex)
    local activeSkin = gameState.ballSkins[ballIndex] or "default"

    -- 构建网格内容
    local gridChildren = {}
    for _, skin in ipairs(skins) do
        local skinKey = ballIndex .. "_" .. skin.id
        local isDefault = skin.isDefault
        local isLocked = (not isDefault) and (not gameState.unlockedSkins[skinKey])
        local isActive = (skin.id == activeSkin)

        local cellBorder
        if isActive then
            cellBorder = { bt.color[1], bt.color[2], bt.color[3], 255 }
        elseif isLocked then
            cellBorder = { 80, 80, 100, 150 }
        else
            cellBorder = { 100, 110, 140, 150 }
        end

        local cellChildren = {
            -- 皮肤展示
            (function()
                if skin.image then
                    -- 图片皮肤：直接显示图片
                    return UI.Panel {
                        width = 48, height = 48,
                        backgroundImage = skin.image,
                        backgroundSize = "contain",
                        pointerEvents = "none",
                    }
                else
                    -- 默认皮肤：显示彩色圆圈
                    return UI.Panel {
                        width = 48, height = 48,
                        justifyContent = "center", alignItems = "center",
                        pointerEvents = "none",
                        children = {
                            UI.Panel {
                                width = 42, height = 42, borderRadius = 21,
                                backgroundColor = bt.color,
                                pointerEvents = "none",
                            },
                        },
                    }
                end
            end)(),
            -- 皮肤名
            UI.Label {
                text = skin.name,
                fontSize = 11,
                fontColor = isLocked and { 120, 120, 140, 180 } or { 210, 220, 240, 240 },
                textAlign = "center",
                marginTop = 2,
            },
        }

        -- 锁定遮罩
        if isLocked then
            table.insert(cellChildren, UI.Panel {
                position = "absolute",
                top = 0, left = 0,
                width = "100%", height = "100%",
                backgroundColor = { 0, 0, 0, 120 },
                borderRadius = 8,
                justifyContent = "center", alignItems = "center",
                pointerEvents = "none",
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 3,
                        children = {
                            UI.Panel {
                                width = 18, height = 18,
                                backgroundImage = "image/icon_ad.png",
                                backgroundSize = "contain",
                            },
                            UI.Label {
                                text = "广告",
                                fontSize = 12,
                                fontColor = { 255, 220, 100, 240 },
                            },
                        },
                    },
                },
            })
        end

        -- 已激活标记
        if isActive then
            table.insert(cellChildren, UI.Panel {
                position = "absolute",
                top = 2, right = 2,
                width = 16, height = 16, borderRadius = 8,
                backgroundColor = { 60, 180, 80, 240 },
                justifyContent = "center", alignItems = "center",
                pointerEvents = "none",
                children = {
                    UI.Label {
                        text = "✓",
                        fontSize = 10,
                        fontColor = { 255, 255, 255, 255 },
                        textAlign = "center",
                    },
                },
            })
        end

        table.insert(gridChildren, UI.Panel {
            width = 72, height = 82,
            backgroundColor = isActive and { bt.color[1], bt.color[2], bt.color[3], 40 } or { 30, 35, 55, 220 },
            borderColor = cellBorder,
            borderWidth = isActive and 2 or 1,
            borderRadius = 8,
            justifyContent = "center", alignItems = "center",
            padding = { 4, 4, 4, 4 },
            pointerEvents = "auto",
            onClick = function()
                cb.PlayClickSfx()
                if isLocked then
                    -- 广告解锁
                    P.AdUnlockSkin(cb, ballIndex, skin.id)
                else
                    -- 选中皮肤
                    gameState.ballSkins[ballIndex] = skin.id
                    State.uiDirty = true
                    cb.ShowSkinPanel(ballIndex) -- 刷新面板
                    cb.RefreshBallItem(ballIndex)
                    if ballIndex == gameState.selectedBallType then
                        cb.UpdateDropButton()
                    end
                    local SaveSystem = require("SaveSystem")
                    SaveSystem.Save()
                end
            end,
            children = cellChildren,
        })
    end

    return UI.Panel {
        id = "skinOverlay",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        pointerEvents = "auto",
        onClick = function()
            cb.PlayClickSfx()
            cb.HideSkinPanel()
        end,
        children = {
            UI.Panel {
                width = "80%",
                backgroundColor = { 20, 25, 50, 245 },
                borderColor = { bt.color[1], bt.color[2], bt.color[3], 180 },
                borderWidth = 2, borderRadius = 12,
                padding = { 16, 18, 14, 18 },
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function() end, -- 阻止穿透
                children = {
                    -- 关闭按钮
                    UI.Panel {
                        position = "absolute",
                        top = 6, right = 8,
                        width = 26, height = 26, borderRadius = 13,
                        backgroundColor = { 50, 55, 80, 200 },
                        justifyContent = "center", alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function()
                            cb.PlayClickSfx()
                            cb.HideSkinPanel()
                        end,
                        children = {
                            UI.Label {
                                text = "×",
                                fontSize = 19,
                                fontColor = { 180, 190, 220, 240 },
                                textAlign = "center",
                            },
                        },
                    },
                    -- 标题
                    UI.Label {
                        text = bt.name .. " 皮肤",
                        fontSize = 20,
                        fontColor = { bt.color[1], bt.color[2], bt.color[3], 255 },
                        textAlign = "center",
                        marginBottom = 12,
                    },
                    -- 网格
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        flexWrap = "wrap",
                        justifyContent = "center",
                        gap = 8,
                        children = gridChildren,
                    },
                    -- 提示
                    UI.Label {
                        text = "点击皮肤可选用，锁定皮肤看广告解锁",
                        fontSize = 12,
                        fontColor = { 120, 130, 160, 160 },
                        textAlign = "center",
                        marginTop = 10,
                    },
                },
            },
        },
    }
end

return P
