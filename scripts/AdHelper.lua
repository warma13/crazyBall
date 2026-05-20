-- ============================================================================
-- AdHelper.lua - 广告调用封装（免广券支持）
-- 所有广告调用统一走 AdHelper.ShowRewardAd()，替代直接 sdk:ShowRewardVideoAd
-- ============================================================================

local UI = require("urhox-libs/UI")
local State = require("State")
local EventBus = require("EventBus")
local SaveSystem = require("SaveSystem")

local gameState = State.gameState

---@diagnostic disable-next-line: undefined-global
local sdk = sdk

local M = {}

--- 播放按钮点击音效（自包含，不依赖外部注入）
local function PlayClickSfx()
    if State.sfxButtonClick and audio then
        local node = State.sfxScene_ and State.sfxScene_:CreateChild("sfx")
        if node then
            local src = node:CreateComponent("SoundSource")
            src.soundType = SOUND_EFFECT
            src.gain = 0.4
            src:Play(State.sfxButtonClick)
            src.autoRemoveMode = REMOVE_NODE
        end
    end
end

--- 获取当前活跃的 UI 根节点（兼容主界面和放置模式）
local function GetActiveRoot()
    return UI.GetRoot()
end

--- 显示免广券选择弹窗
---@param onResult fun(result: table)  与 sdk:ShowRewardVideoAd 回调格式一致
local function ShowTicketPopup(onResult)
    local root = GetActiveRoot()
    if not root then return end

    -- 移除旧弹窗
    local old = root:FindById("adTicketOverlay")
    if old then root:RemoveChild(old) end

    local tickets = gameState.adFreeTickets or 0

    local function dismiss()
        local r = GetActiveRoot()
        if not r then return end
        local el = r:FindById("adTicketOverlay")
        if el then r:RemoveChild(el) end
    end

    root:AddChild(UI.Panel {
        id = "adTicketOverlay",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 180 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = "78%",
                backgroundColor = { 20, 28, 50, 250 },
                borderWidth = 2,
                borderColor = { 80, 140, 255, 180 },
                borderRadius = 16,
                padding = { 22, 24, 18, 24 },
                alignItems = "center",
                gap = 14,
                children = {
                    -- 标题
                    UI.Label {
                        text = "免广券",
                        fontSize = 20,
                        fontWeight = "bold",
                        fontColor = { 255, 220, 80, 255 },
                    },
                    -- 剩余数量
                    UI.Label {
                        text = "剩余: " .. State.FormatNumber(tickets) .. " 张",
                        fontSize = 14,
                        fontColor = { 180, 190, 210, 220 },
                    },
                    -- 使用免广券按钮
                    UI.Panel {
                        width = "100%",
                        padding = { 14, 12, 14, 12 },
                        backgroundColor = { 60, 160, 80, 240 },
                        borderRadius = 10,
                        justifyContent = "center", alignItems = "center",
                        pointerEvents = "auto",
                        marginTop = 4,
                        onClick = function()
                            PlayClickSfx()
                            dismiss()
                            -- 扣券
                            gameState.adFreeTickets = (gameState.adFreeTickets or 0) - 1
                            SaveSystem.Save()
                            SaveSystem.Flush()
                            -- 直接返回成功
                            gameState.paused = false
                            onResult({ success = true })
                        end,
                        children = {
                            UI.Label {
                                text = "使用免广券",
                                fontSize = 16,
                                fontWeight = "bold",
                                fontColor = { 255, 255, 255, 255 },
                            },
                        },
                    },
                    -- 观看广告按钮
                    UI.Panel {
                        width = "100%",
                        padding = { 14, 12, 14, 12 },
                        backgroundColor = { 220, 140, 30, 240 },
                        borderRadius = 10,
                        justifyContent = "center", alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function()
                            PlayClickSfx()
                            dismiss()
                            -- 走正常广告流程
                            sdk:ShowRewardVideoAd(function(result)
                                gameState.paused = false
                                onResult(result)
                                if result.success then
                                    SaveSystem.Save()
                                    SaveSystem.Flush()
                                end
                            end)
                        end,
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                alignItems = "center", justifyContent = "center",
                                gap = 6,
                                children = {
                                    UI.Panel {
                                        width = 22, height = 22,
                                        backgroundImage = "image/icon_ad.png",
                                        backgroundSize = "contain",
                                    },
                                    UI.Label {
                                        text = "观看广告",
                                        fontSize = 16,
                                        fontWeight = "bold",
                                        fontColor = { 255, 255, 255, 255 },
                                    },
                                },
                            },
                        },
                    },
                    -- 取消按钮
                    UI.Panel {
                        width = "100%",
                        padding = { 10, 10, 10, 10 },
                        borderRadius = 10,
                        justifyContent = "center", alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function()
                            PlayClickSfx()
                            dismiss()
                            gameState.paused = false
                            onResult({ success = false })
                        end,
                        children = {
                            UI.Label {
                                text = "取消",
                                fontSize = 14,
                                fontColor = { 140, 150, 170, 180 },
                            },
                        },
                    },
                },
            },
        },
    })
end

--- 统一广告入口（替代 sdk:ShowRewardVideoAd）
--- 有免广券时弹窗选择；无券时直接播广告
---@param callback fun(result: table)  result.success = true/false
function M.ShowRewardAd(callback)
    gameState.paused = true

    local tickets = gameState.adFreeTickets or 0
    if tickets > 0 then
        -- 有券，弹窗让用户选择
        ShowTicketPopup(callback)
    else
        -- 无券，直接播广告
        sdk:ShowRewardVideoAd(function(result)
            gameState.paused = false
            callback(result)
            if result.success then
                SaveSystem.Save()
                SaveSystem.Flush()
            end
        end)
    end
end

return M
