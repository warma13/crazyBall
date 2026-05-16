-- ============================================================================
-- GameUI.lua - UI 协调器（门面模块）
-- 将 UI 构建委托给 scripts/UI/ 下的子模块，自身只保留：
--   1. 根布局 (CreateUI / CreateUpgradePanel / CreateDropCircleButton)
--   2. TabBar + 滚动记忆
--   3. Show/Hide 弹窗包装
--   4. 局部刷新 + 事件订阅
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local BigNum = require("BigNum")
local State = require("State")
local Slots = require("Slots")
local Upgrades = require("Upgrades")
local EventBus = require("EventBus")
local Leaderboard = require("Leaderboard")

-- 子模块
local BallPanel = require("UI.BallPanel")
local PocketPanel = require("UI.PocketPanel")
local EffectPanel = require("UI.EffectPanel")
local SettingsPanel = require("UI.SettingsPanel")
local FailedPanel = require("UI.FailedPanel")
local SkinPanel = require("UI.SkinPanel")
local LeaderboardPanel = require("UI.LeaderboardPanel")
local RunePanel = require("UI.RunePanel")
local Runes = require("Runes")
local Enchantment = require("Enchantment")

local CONFIG = Config.CONFIG
local gameState = State.gameState

local PlatformUtils = require("urhox-libs.Platform.PlatformUtils")

local M = {}

---@diagnostic disable-next-line: undefined-global
local sdk = sdk
local ADS_ENABLED = true   -- 广告入口总开关

-- 物理模块引用（由 main.lua 注入，解决循环依赖）
M.Physics = nil

-- 新手教程状态
local tutorialVisible = false
local tutorialPanel = nil

-- 弹窗状态
local leaderboardOpen = false
local settingsOpen = false

-- 各 tab 的滚动位置记忆
local tabScrollY = { balls = 0, pockets = 0, upgrades = 0, runes = 0 }
local pendingRestore = nil  -- { tab, y, frames }

--- 播放按钮点击音效
local function PlayClickSfx()
    if State.sfxButtonClick and M.Physics then
        M.Physics.PlaySfx(State.sfxButtonClick, 0.4)
    end
end

-- ============================================================================
-- 回调表（延迟绑定，子模块通过闭包访问协调器方法）
-- ============================================================================
local cb = {
    PlayClickSfx = PlayClickSfx,
    ADS_ENABLED   = ADS_ENABLED,

    -- 弹窗 Show/Hide（闭包延迟绑定，定义顺序无关）
    ShowSettingsPanel     = function()          M.ShowSettingsPanel() end,
    HideSettingsPanel     = function()          M.HideSettingsPanel() end,
    ShowSkinPanel         = function(idx)       M.ShowSkinPanel(idx) end,
    HideSkinPanel         = function()          M.HideSkinPanel() end,
    HideLeaderboardPanel  = function()          M.HideLeaderboardPanel() end,
    RefreshLeaderboardPanel = function()        M.RefreshLeaderboardPanel() end,
    HideFailedPanel       = function()          M.HideFailedPanel() end,
    OnFailedRestart       = function(flag, c, g)
        if M.OnFailedRestart then M.OnFailedRestart(flag, c, g) end
    end,

    -- 符文重新开始确认
    ShowRuneRestartConfirm = function() M.ShowRuneRestartConfirm() end,

    -- 局部刷新
    RefreshBallItem  = function(idx) M.RefreshBallItem(idx) end,
    UpdateDropButton = function()    M.UpdateDropButton() end,
}

-- ============================================================================
-- 根布局
-- ============================================================================

--- 创建根 UI
function M.CreateUI()
    local splitPct = math.floor(CONFIG.BOARD_SPLIT_RATIO * 100) .. "%"
    State.uiRoot_ = UI.SafeAreaView {
        id = "gameRoot",
        width = "100%",
        height = "100%",
        edges = { "top" },
        mode = "padding",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                width = "100%",
                height = splitPct,
                pointerEvents = "none",
            },
            M.CreateUpgradePanel(),
            M.CreateDropCircleButton(),
        }
    }
    UI.SetRoot(State.uiRoot_)
    M.SubscribeEvents()
end

function M.CreateUpgradePanel()
    local fixedBtnChildren = {}
    if gameState.activeTab == "upgrades" then
        table.insert(fixedBtnChildren, EffectPanel.CreateDrawButton(cb))
    elseif gameState.activeTab == "balls" then
        -- 80% 一键升级 + 20% 附魔，横向排列
        local bulkBtn = EffectPanel.CreateBulkUpgradeButton(cb)
        bulkBtn:SetStyle({ width = "80%" })
        table.insert(fixedBtnChildren, bulkBtn)
        table.insert(fixedBtnChildren, EffectPanel.CreateEnchantButton(cb))
    elseif gameState.activeTab == "pockets" then
        table.insert(fixedBtnChildren, EffectPanel.CreateBulkUpgradeButton(cb))
    end

    local drawBtnDir = (gameState.activeTab == "balls") and "row" or "column"

    return UI.Panel {
        id = "upgradePanel",
        width = "100%",
        flexGrow = 1,
        backgroundColor = { 18, 22, 40, 245 },
        borderColor = { 70, 90, 140, 220 },
        borderWidth = { 2, 0, 0, 0 },
        children = {
            UI.ScrollView {
                id = "tabContent",
                width = "100%",
                flexGrow = 1,
                padding = { 10, 14, 6, 14 },
                onScroll = function(self, sx, sy)
                    if not pendingRestore then
                        tabScrollY[gameState.activeTab] = sy
                    end
                end,
                children = { M.CreateTabContent() },
            },
            UI.Panel {
                id = "drawBtnFixed",
                width = "100%",
                flexDirection = drawBtnDir,
                padding = { 0, 6, 6, 6 },
                gap = 4,
                children = fixedBtnChildren,
            },
            M.CreateTabBar(),
        }
    }
end

function M.CreateDropCircleButton()
    local circleSize = 64
    local tabBarH = 42
    local bottomOffset = tabBarH + 6

    local bt = Config.BALL_TYPES[gameState.selectedBallType]

    -- 投弹按钮面板
    local dropBtnPanel = UI.Panel {
        width = "100%",
        alignItems = "center",
        marginBottom = bottomOffset,
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                id = "dropOuter",
                width = circleSize + 10, height = circleSize + 10,
                borderRadius = (circleSize + 10) / 2,
                backgroundColor = { bt.color[1], bt.color[2], bt.color[3], 35 },
                justifyContent = "center", alignItems = "center",
                pointerEvents = "box-none",
                children = {
                    UI.Panel {
                        id = "dropCircle",
                        width = circleSize, height = circleSize,
                        borderRadius = circleSize / 2,
                        backgroundColor = { 25, 30, 55, 140 },
                        borderColor = { bt.color[1], bt.color[2], bt.color[3], 200 },
                        borderWidth = 2.5,
                        justifyContent = "center", alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function()
                            if gameState.roundPhase == "failed" then return end
                            PlayClickSfx()
                            M.HideTutorial()
                            if M.Physics then
                                local dropped = M.Physics.DropMultipleBalls(true)
                                if dropped == 0 then
                                    gameState.failedToast = { timer = 1.5, text = "金币不足", offsetY = 0 }
                                end
                            end
                        end,
                        children = {
                            (function()
                                local activeSkin = gameState.ballSkins[gameState.selectedBallType] or "default"
                                if activeSkin ~= "default" and bt.skinKey then
                                    return UI.Panel {
                                        id = "dropBallDot",
                                        width = 30, height = 30,
                                        backgroundImage = Config.GetBallSkinImage(bt.skinKey),
                                        backgroundSize = "contain",
                                        pointerEvents = "none",
                                    }
                                else
                                    return UI.Panel {
                                        id = "dropBallDot",
                                        width = 24, height = 24, borderRadius = 12,
                                        backgroundColor = bt.color,
                                        pointerEvents = "none",
                                    }
                                end
                            end)(),
                        }
                    },
                }
            },
        }
    }

    -- 新手教程
    local outerChildren = {}
    if gameState.round == 1 and gameState.drawCount == 0 then
        tutorialVisible = true
        local isMobile = PlatformUtils.IsMobilePlatform()
        local hintText = "👆 点击投弹"
        if not isMobile then
            hintText = "👆 点击投弹 / 按空格键"
        end
        tutorialPanel = UI.Panel {
            id = "tutorialHint",
            position = "absolute",
            bottom = bottomOffset + circleSize + 16,
            width = "100%",
            alignItems = "center",
            pointerEvents = "none",
            children = {
                UI.Panel {
                    backgroundColor = { 255, 200, 50, 220 },
                    borderRadius = 12,
                    padding = { 8, 16, 8, 16 },
                    children = {
                        UI.Label {
                            text = hintText,
                            fontSize = 15,
                            color = { 30, 20, 10, 255 },
                            fontWeight = "bold",
                        },
                    }
                },
                UI.Label {
                    text = "▼",
                    fontSize = 20,
                    color = { 255, 200, 50, 220 },
                    marginTop = -4,
                },
            }
        }
        table.insert(outerChildren, tutorialPanel)
    end

    table.insert(outerChildren, dropBtnPanel)

    return UI.Panel {
        position = "absolute",
        bottom = 0,
        width = "100%",
        height = bottomOffset + circleSize + 100,
        alignItems = "center",
        justifyContent = "flex-end",
        pointerEvents = "box-none",
        children = outerChildren,
    }
end

--- 隐藏新手教程提示
function M.HideTutorial()
    if tutorialVisible and tutorialPanel then
        tutorialPanel:SetVisible(false)
        tutorialVisible = false
    end
end

-- ============================================================================
-- TabBar + 滚动记忆
-- ============================================================================

function M.CreateTabBar()
    return UI.Panel {
        id = "tabBar",
        width = "100%",
        flexDirection = "row",
        height = 42,
        borderColor = { 50, 60, 90, 200 },
        borderWidth = { 1, 0, 0, 0 },
        children = {
            M.CreateTabButton("钢珠", "balls"),
            M.CreateTabButton("口袋", "pockets"),
            M.CreateTabButton("升级", "upgrades"),
            M.CreateTabButton("符文", "runes"),
        }
    }
end

function M.CreateTabButton(label, tabKey)
    local isActive = (gameState.activeTab == tabKey)
    return UI.Panel {
        id = "tab_" .. tabKey,
        flexGrow = 1, flexBasis = 0,
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = isActive and { 35, 45, 75, 255 } or { 18, 22, 40, 255 },
        borderColor = isActive and { 90, 130, 220, 255 } or { 40, 50, 70, 0 },
        borderWidth = { isActive and 2 or 0, 0, 0, 0 },
        pointerEvents = "auto",
        onClick = function()
            PlayClickSfx()
            if gameState.activeTab ~= tabKey then
                M.SaveTabScroll()
                gameState.activeTab = tabKey
                EventBus.emit("tab_changed")
                M.RestoreTabScroll()
            end
        end,
        children = {
            UI.Label {
                id = "tabLabel_" .. tabKey,
                text = label,
                fontSize = 17,
                fontColor = isActive
                    and { 180, 210, 255, 255 }
                    or { 100, 110, 140, 200 },
                textAlign = "center",
            },
        }
    }
end

function M.CreateTabContent()
    if gameState.activeTab == "balls" then
        return BallPanel.CreateBallSelectionRow(cb)
    elseif gameState.activeTab == "pockets" then
        return PocketPanel.CreatePocketUpgradeRow(cb)
    elseif gameState.activeTab == "runes" then
        return RunePanel.CreateRuneUpgradeRow(cb)
    else
        return EffectPanel.CreateGlobalUpgradeRow(cb)
    end
end

function M.SaveTabScroll()
    local sv = State.uiRoot_ and State.uiRoot_:FindById("tabContent")
    if sv then
        local _, sy = sv:GetScroll()
        tabScrollY[gameState.activeTab] = sy or 0
    end
end

function M.RestoreTabScroll()
    local y = tabScrollY[gameState.activeTab] or 0
    pendingRestore = { tab = gameState.activeTab, y = y, frames = 4 }
    local sv = State.uiRoot_ and State.uiRoot_:FindById("tabContent")
    if sv then
        sv:SetScrollDirect(0, y)
        sv.state.velocityY = 0
    end
end

function M.Update(dt)
    if pendingRestore then
        local sv = State.uiRoot_ and State.uiRoot_:FindById("tabContent")
        if sv and gameState.activeTab == pendingRestore.tab then
            sv.state.scrollY = pendingRestore.y
            sv.state.velocityY = 0
        end
        pendingRestore.frames = pendingRestore.frames - 1
        if pendingRestore.frames <= 0 then
            pendingRestore = nil
        end
    end
end

-- ============================================================================
-- 弹窗 Show/Hide 包装
-- ============================================================================

--- 切换设置面板
function M.ToggleSettings()
    PlayClickSfx()
    settingsOpen = not settingsOpen
    if settingsOpen then
        gameState.paused = true
        M.ShowSettingsPanel()
    else
        gameState.paused = false
        M.HideSettingsPanel()
    end
end

function M.ShowSettingsPanel()
    if not State.uiRoot_ then return end
    local old = State.uiRoot_:FindById("settingsOverlay")
    if old then State.uiRoot_:RemoveChild(old) end
    State.uiRoot_:AddChild(SettingsPanel.CreateSettingsPanel(cb))
end

function M.HideSettingsPanel()
    if not State.uiRoot_ then return end
    local old = State.uiRoot_:FindById("settingsOverlay")
    if old then State.uiRoot_:RemoveChild(old) end
    settingsOpen = false
    gameState.paused = false
    local SaveSystem = require("SaveSystem")
    SaveSystem.Save()
end

-- 失败弹窗
M.OnFailedRestart = nil

function M.ShowFailedPanel(info)
    if not State.uiRoot_ then return end
    local old = State.uiRoot_:FindById("failedOverlay")
    if old then State.uiRoot_:RemoveChild(old) end
    State.uiRoot_:AddChild(FailedPanel.CreateFailedPanel(cb, info))
end

function M.HideFailedPanel()
    if not State.uiRoot_ then return end
    local old = State.uiRoot_:FindById("failedOverlay")
    if old then State.uiRoot_:RemoveChild(old) end
end

-- 符文重新开始确认弹窗
M.OnRuneRestart = nil

function M.ShowRuneRestartConfirm()
    if not State.uiRoot_ then return end
    local old = State.uiRoot_:FindById("runeRestartOverlay")
    if old then State.uiRoot_:RemoveChild(old) end

    local reward = Runes.PreviewEssenceReward(gameState.round - 1)
    local doubleReward = reward * 2
    local carryCoins = BigNum.floor(gameState.coins * 0.2)
    local carryGems = math.floor(State.GetGems() * 0.2)

    -- 构建广告按钮（条件显示）
    local adChildren = {}
    if ADS_ENABLED and reward > 0 then
        table.insert(adChildren, UI.Panel {
            width = "100%",
            padding = { 13, 12, 13, 12 },
            backgroundColor = { 220, 140, 30, 240 },
            borderRadius = 10,
            justifyContent = "center", alignItems = "center",
            pointerEvents = "auto",
            marginBottom = 8,
            onClick = function()
                PlayClickSfx()
                gameState.paused = true
                sdk:ShowRewardVideoAd(function(result)
                    gameState.paused = false
                    if result.success then
                        M.HideRuneRestartConfirm()
                        if M.OnRuneRestart then
                            M.OnRuneRestart(true, carryCoins, carryGems)
                        end
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
                            width = 28, height = 28,
                            backgroundImage = "image/icon_ad.png",
                            backgroundSize = "contain",
                        },
                        UI.Label {
                            text = "广告：双倍精粹 + 携带资源",
                            fontSize = 15,
                            fontColor = { 255, 255, 255, 255 },
                            fontWeight = "bold",
                        },
                    },
                },
                UI.Label {
                    text = string.format("+%d精粹  携带20%%金币和宝石", doubleReward),
                    fontSize = 12,
                    fontColor = { 255, 240, 200, 220 },
                    marginTop = 4,
                },
            },
        })
    end

    -- 构建弹窗内容列表
    local dialogChildren = {
        UI.Label {
            text = "确认重新开始？",
            fontSize = 20,
            fontColor = { 220, 200, 255, 255 },
            fontWeight = "bold",
        },
        UI.Label {
            text = string.format("当前第 %d 轮", gameState.round),
            fontSize = 13,
            fontColor = { 160, 170, 200, 200 },
            marginTop = 8,
        },
        UI.Panel {
            width = "100%", height = 1,
            backgroundColor = { 80, 90, 130, 100 },
            marginTop = 14, marginBottom = 14,
        },
        UI.Label {
            text = "放弃当前进度，获得符文精粹",
            fontSize = 13,
            fontColor = { 200, 190, 230, 200 },
        },
        UI.Panel {
            flexDirection = "row",
            alignItems = "center", justifyContent = "center",
            gap = 6,
            marginTop = 8, marginBottom = 16,
            children = {
                UI.Label {
                    text = string.format("+%d 精粹", reward),
                    fontSize = 22,
                    fontColor = { 200, 160, 255, 255 },
                    fontWeight = "bold",
                },
            },
        },
    }

    -- 广告按钮（双倍精粹+携带资源）
    for _, child in ipairs(adChildren) do
        table.insert(dialogChildren, child)
    end

    -- 确认按钮
    table.insert(dialogChildren, UI.Panel {
        width = "100%",
        padding = { 12, 10, 12, 10 },
        backgroundColor = { 180, 60, 60, 230 },
        borderRadius = 10,
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onClick = function()
            PlayClickSfx()
            M.HideRuneRestartConfirm()
            if M.OnRuneRestart then M.OnRuneRestart(false) end
        end,
        children = {
            UI.Label {
                text = "确认重新开始",
                fontSize = 16,
                fontColor = { 255, 255, 255, 255 },
                fontWeight = "bold",
            },
        },
    })

    -- 取消按钮
    table.insert(dialogChildren, UI.Panel {
        width = "100%",
        padding = { 10, 8, 10, 8 },
        backgroundColor = { 50, 55, 80, 220 },
        borderColor = { 80, 90, 120, 150 },
        borderWidth = 1, borderRadius = 10,
        justifyContent = "center", alignItems = "center",
        marginTop = 8,
        pointerEvents = "auto",
        onClick = function()
            PlayClickSfx()
            M.HideRuneRestartConfirm()
        end,
        children = {
            UI.Label {
                text = "取消",
                fontSize = 14,
                fontColor = { 160, 170, 200, 220 },
            },
        },
    })

    State.uiRoot_:AddChild(UI.Panel {
        id = "runeRestartOverlay",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        pointerEvents = "auto",
        children = {
            UI.Panel {
                width = "80%",
                backgroundColor = { 25, 30, 55, 250 },
                borderColor = { 180, 140, 255, 180 },
                borderWidth = 2, borderRadius = 14,
                padding = { 20, 22, 16, 22 },
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function() end,
                children = dialogChildren,
            },
        },
    })
end

function M.HideRuneRestartConfirm()
    if not State.uiRoot_ then return end
    local old = State.uiRoot_:FindById("runeRestartOverlay")
    if old then State.uiRoot_:RemoveChild(old) end
end

-- 皮肤面板
function M.ShowSkinPanel(ballIndex)
    if not State.uiRoot_ then return end
    M.HideSkinPanel()
    State.uiRoot_:AddChild(SkinPanel.CreateSkinPanel(cb, ballIndex))
end

function M.HideSkinPanel()
    if not State.uiRoot_ then return end
    local old = State.uiRoot_:FindById("skinOverlay")
    if old then State.uiRoot_:RemoveChild(old) end
end

function M.AdUnlockSkin(ballIndex, skinId)
    SkinPanel.AdUnlockSkin(cb, ballIndex, skinId)
end

-- 排行榜弹窗
function M.ToggleLeaderboard()
    PlayClickSfx()
    leaderboardOpen = not leaderboardOpen
    if leaderboardOpen then
        Leaderboard.FetchRankList(function()
            M.RefreshLeaderboardPanel()
        end)
        M.ShowLeaderboardPanel()
    else
        M.HideLeaderboardPanel()
    end
end

function M.ShowLeaderboardPanel()
    if not State.uiRoot_ then return end
    local old = State.uiRoot_:FindById("lbOverlay")
    if old then State.uiRoot_:RemoveChild(old) end
    State.uiRoot_:AddChild(LeaderboardPanel.CreateLeaderboardPanel(cb))
end

function M.HideLeaderboardPanel()
    if not State.uiRoot_ then return end
    local old = State.uiRoot_:FindById("lbOverlay")
    if old then State.uiRoot_:RemoveChild(old) end
    leaderboardOpen = false
end

function M.RefreshLeaderboardPanel()
    if not leaderboardOpen then return end
    if not State.uiRoot_ then return end
    local old = State.uiRoot_:FindById("lbOverlay")
    if old then State.uiRoot_:RemoveChild(old) end
    State.uiRoot_:AddChild(LeaderboardPanel.CreateLeaderboardPanel(cb))
end

-- ============================================================================
-- 局部刷新
-- ============================================================================

local function ReplaceItemById(listId, itemId, newItem)
    if not State.uiRoot_ then return false end
    local list = State.uiRoot_:FindById(listId)
    if not list then return false end
    local children = list:GetChildren()
    for i, child in ipairs(children) do
        if child.id == itemId then
            list:RemoveChild(child)
            list:InsertChild(newItem, i)
            return true
        end
    end
    return false
end

function M.RefreshBallItem(index)
    ReplaceItemById("ballList", "ball_" .. index, BallPanel.CreateBallButton(cb, index))
end

function M.RefreshPocketItem(index)
    ReplaceItemById("pocketList", "pocket_" .. index, PocketPanel.CreatePocketItem(cb, index))
end

function M.RefreshEffectItem(effId)
    for _, eff in ipairs(Config.DRAW_EFFECTS) do
        if eff.id == effId then
            ReplaceItemById("effectList", "eff_" .. effId, EffectPanel.CreateEffectItem(cb, eff))
            break
        end
    end
end

function M.RefreshDrawButton()
    if not State.uiRoot_ then return end
    local drawArea = State.uiRoot_:FindById("drawBtnFixed")
    if drawArea and gameState.activeTab == "upgrades" then
        drawArea:ClearChildren()
        drawArea:AddChild(EffectPanel.CreateDrawButton(cb))
    end
end

-- affordability 缓存：跳过「是否买得起」无变化的刷新
local lastAffordKey = ""

--- 计算当前 tab 所有 item 的 canAfford 位图
local function ComputeAffordKey()
    local tab = gameState.activeTab
    if tab == "balls" then
        local bits = {}
        for i = 1, #Config.BALL_TYPES do
            local bt = Config.BALL_TYPES[i]
            local level = gameState.ballLevels[i]
            local isUnlocked = level > 0
            local isAdOnly = bt.adOnly and not isUnlocked
            if isAdOnly then
                bits[i] = "x"
            else
                local cost = isUnlocked and Upgrades.GetBallUpgradeCost(i) or bt.cost
                bits[i] = (gameState.coins >= cost) and "1" or "0"
            end
        end
        return "B" .. table.concat(bits)
    elseif tab == "pockets" then
        local bits = {}
        for i = 1, #gameState.slots do
            local cost = Slots.GetSlotUpgradeCost(gameState.slots[i])
            bits[i] = (gameState.coins >= cost) and "1" or "0"
        end
        return "P" .. table.concat(bits)
    elseif tab == "upgrades" then
        local bits = {}
        local gems = State.GetGems()
        for _, eff in ipairs(Config.DRAW_EFFECTS) do
            if Upgrades.HasEffect(eff.id) then
                local cost = Upgrades.GetEffectUpgradeCost(eff.id)
                table.insert(bits, (cost and gems >= cost) and "1" or "0")
            end
        end
        return "U" .. table.concat(bits)
    end
    return ""
end

function M.RefreshAllItemsInCurrentTab()
    if not State.uiRoot_ then return end

    -- 缓存检查：canAfford 状态无变化则跳过整次刷新
    local key = ComputeAffordKey()
    if key == lastAffordKey then return end
    lastAffordKey = key

    if gameState.activeTab == "balls" then
        for i = 1, #Config.BALL_TYPES do
            M.RefreshBallItem(i)
        end
    elseif gameState.activeTab == "pockets" then
        for i = 1, #gameState.slots do
            M.RefreshPocketItem(i)
        end
    elseif gameState.activeTab == "upgrades" then
        for _, eff in ipairs(Config.DRAW_EFFECTS) do
            if Upgrades.HasEffect(eff.id) then
                M.RefreshEffectItem(eff.id)
            end
        end
        M.RefreshDrawButton()
    end
end

function M.RefreshTabContent()
    if not State.uiRoot_ then return end
    lastAffordKey = ""  -- 全量重建时清除缓存
    local sv = State.uiRoot_:FindById("tabContent")
    if sv then
        sv:ClearChildren()
        sv:AddChild(M.CreateTabContent())
    end
    local drawArea = State.uiRoot_:FindById("drawBtnFixed")
    if drawArea then
        drawArea:ClearChildren()
        if gameState.activeTab == "upgrades" then
            drawArea:SetStyle({ flexDirection = "column", gap = 0 })
            drawArea:AddChild(EffectPanel.CreateDrawButton(cb))
        elseif gameState.activeTab == "balls" then
            drawArea:SetStyle({ flexDirection = "row", gap = 4 })
            local bulkBtn = EffectPanel.CreateBulkUpgradeButton(cb)
            bulkBtn:SetStyle({ width = "80%" })
            drawArea:AddChild(bulkBtn)
            drawArea:AddChild(EffectPanel.CreateEnchantButton(cb))
        elseif gameState.activeTab == "pockets" then
            drawArea:SetStyle({ flexDirection = "column", gap = 0 })
            drawArea:AddChild(EffectPanel.CreateBulkUpgradeButton(cb))
        end
    end
end

function M.UpdateTabBar()
    if not State.uiRoot_ then return end
    local tabs = { "balls", "pockets", "upgrades", "runes" }
    for _, key in ipairs(tabs) do
        local isActive = (gameState.activeTab == key)
        local tabBtn = State.uiRoot_:FindById("tab_" .. key)
        if tabBtn then
            tabBtn:SetStyle({
                backgroundColor = isActive and { 35, 45, 75, 255 } or { 18, 22, 40, 255 },
                borderColor = isActive and { 90, 130, 220, 255 } or { 40, 50, 70, 0 },
                borderWidth = { isActive and 2 or 0, 0, 0, 0 },
            })
        end
        local tabLabel = State.uiRoot_:FindById("tabLabel_" .. key)
        if tabLabel then
            tabLabel:SetStyle({
                fontColor = isActive
                    and { 180, 210, 255, 255 }
                    or { 100, 110, 140, 200 },
            })
        end
    end
end

function M.UpdateDropButton()
    if not State.uiRoot_ then return end
    local bt = Config.BALL_TYPES[gameState.selectedBallType]
    local outer = State.uiRoot_:FindById("dropOuter")
    if outer then
        outer:SetStyle({ backgroundColor = { bt.color[1], bt.color[2], bt.color[3], 35 } })
    end
    local circle = State.uiRoot_:FindById("dropCircle")
    if circle then
        circle:SetStyle({ borderColor = { bt.color[1], bt.color[2], bt.color[3], 200 } })
    end
    local dot = State.uiRoot_:FindById("dropBallDot")
    if dot then
        local activeSkin = gameState.ballSkins[gameState.selectedBallType] or "default"
        if activeSkin ~= "default" and bt.skinKey then
            dot:SetStyle({
                width = 30, height = 30, borderRadius = 0,
                backgroundColor = { 0, 0, 0, 0 },
                backgroundImage = Config.GetBallSkinImage(bt.skinKey),
                backgroundSize = "contain",
            })
        else
            dot:SetStyle({
                width = 24, height = 24, borderRadius = 12,
                backgroundColor = bt.color,
                backgroundImage = "",
            })
        end
    end
end

-- ============================================================================
-- 事件订阅
-- ============================================================================
function M.SubscribeEvents()
    EventBus.on("tab_changed", function()
        M.UpdateTabBar()
        M.RefreshTabContent()
    end)

    EventBus.on("ball_changed", function(data)
        M.UpdateDropButton()
        if gameState.activeTab == "balls" and data then
            M.RefreshBallItem(data.index)
            if data.prevSelected and data.prevSelected ~= data.index then
                M.RefreshBallItem(data.prevSelected)
            end
            if data.coinsSpent then
                for i = 1, #Config.BALL_TYPES do
                    if i ~= data.index and i ~= data.prevSelected then
                        M.RefreshBallItem(i)
                    end
                end
            end
        end
        -- else: 不在 balls tab 时无需刷新，切回时 tab_changed 会全量重建
    end)

    EventBus.on("slot_changed", function(data)
        if gameState.activeTab == "pockets" and data then
            M.RefreshPocketItem(data.index)
            for i = 1, #gameState.slots do
                if i ~= data.index then
                    M.RefreshPocketItem(i)
                end
            end
        end
        -- else: 不在 pockets tab 时无需刷新，切回时 tab_changed 会全量重建
    end)

    EventBus.on("slot_added", function()
        M.RefreshTabContent()
    end)

    EventBus.on("effect_upgraded", function(data)
        if gameState.activeTab == "upgrades" and data then
            M.RefreshEffectItem(data.id)
            for _, eff in ipairs(Config.DRAW_EFFECTS) do
                if eff.id ~= data.id and Upgrades.HasEffect(eff.id) then
                    M.RefreshEffectItem(eff.id)
                end
            end
            M.RefreshDrawButton()
        end
        -- else: 不在 upgrades tab 时无需刷新，切回时 tab_changed 会全量重建
    end)

    EventBus.on("effect_drawn", function(data)
        if gameState.activeTab == "upgrades" then
            M.RefreshTabContent()
        end
        -- else: 不在 upgrades tab 时无需刷新，切回时 tab_changed 会全量重建
    end)

    EventBus.on("rune_upgraded", function()
        if gameState.activeTab == "runes" then
            M.RefreshTabContent()
        end
    end)

    EventBus.on("round_started", function()
        M.RefreshTabContent()
    end)

    EventBus.on("enchant_changed", function(data)
        -- 刷新附魔按钮
        if State.uiRoot_ then
            local drawArea = State.uiRoot_:FindById("drawBtnFixed")
            if drawArea and gameState.activeTab == "balls" then
                drawArea:ClearChildren()
                drawArea:SetStyle({ flexDirection = "row", gap = 4 })
                local bulkBtn = EffectPanel.CreateBulkUpgradeButton(cb)
                bulkBtn:SetStyle({ width = "80%" })
                drawArea:AddChild(bulkBtn)
                drawArea:AddChild(EffectPanel.CreateEnchantButton(cb))
            end
        end
        -- 刷新球列表中对应球
        if gameState.activeTab == "balls" and data then
            M.RefreshBallItem(data.ballIndex)
        end
        -- 显示附魔结果弹窗
        if data then
            M.ShowEnchantResult(data)
        end
    end)
end

-- ============================================================================
-- 附魔结果弹窗
-- ============================================================================

function M.ShowEnchantResult(data)
    if not State.uiRoot_ then return end
    M.HideEnchantResult()

    local enchant = data.enchant
    local newLevel = data.newLevel
    local isUpgrade = data.isUpgrade

    local titleText = isUpgrade and "附魔升级！" or "获得附魔！"
    local titleColor = isUpgrade and { 255, 200, 50, 255 } or { 100, 220, 255, 255 }

    local descText = enchant.descFunc(newLevel)

    State.uiRoot_:AddChild(UI.Panel {
        id = "enchantResultOverlay",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        pointerEvents = "auto",
        onClick = function() M.HideEnchantResult() end,
        children = {
            UI.Panel {
                width = "75%",
                backgroundColor = { 25, 30, 55, 250 },
                borderColor = { enchant.color[1], enchant.color[2], enchant.color[3], 200 },
                borderWidth = 2, borderRadius = 14,
                padding = { 20, 20, 16, 20 },
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function() end,  -- 阻止穿透
                children = {
                    UI.Label {
                        text = titleText,
                        fontSize = 20,
                        fontColor = titleColor,
                        fontWeight = "bold",
                    },
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 90, 130, 100 },
                        marginTop = 12, marginBottom = 12,
                    },
                    UI.Label {
                        text = enchant.icon .. " " .. enchant.name,
                        fontSize = 24,
                        fontColor = { enchant.color[1], enchant.color[2], enchant.color[3], 255 },
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = "Lv." .. newLevel,
                        fontSize = 18,
                        fontColor = { 220, 220, 240, 220 },
                        marginTop = 6,
                    },
                    UI.Label {
                        text = descText,
                        fontSize = 14,
                        fontColor = { 180, 190, 220, 200 },
                        marginTop = 8,
                        textAlign = "center",
                    },
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = { 80, 90, 130, 100 },
                        marginTop = 14, marginBottom = 10,
                    },
                    UI.Panel {
                        width = "100%",
                        padding = { 10, 8, 10, 8 },
                        backgroundColor = { 50, 70, 110, 220 },
                        borderRadius = 10,
                        justifyContent = "center", alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function()
                            PlayClickSfx()
                            M.HideEnchantResult()
                        end,
                        children = {
                            UI.Label {
                                text = "确定",
                                fontSize = 16,
                                fontColor = { 200, 220, 255, 255 },
                                fontWeight = "bold",
                            },
                        },
                    },
                },
            },
        },
    })
end

function M.HideEnchantResult()
    if not State.uiRoot_ then return end
    local old = State.uiRoot_:FindById("enchantResultOverlay")
    if old then State.uiRoot_:RemoveChild(old) end
end

return M
