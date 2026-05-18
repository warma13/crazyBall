-- ============================================================================
-- DebugPanel.lua - 调试面板（点击右上角用户ID打开）
-- 提供：解锁下一关、获取球币、获取金币
-- ============================================================================

local UI = require("urhox-libs/UI")
local State = require("State")
local BigNum = require("BigNum")

local gameState = State.gameState
local M = {}

local debugOverlay_ = nil
local currentRoot_  = nil

--- 设置当前 UI 根节点（创建 UI 后调用）
function M.SetRoot(root)
    currentRoot_ = root
end

--- 创建右上角透明点击区域（覆盖在用户ID上方）
function M.CreateDebugTrigger()
    return UI.Panel {
        position = "absolute",
        top = 0, right = 0,
        width = 120, height = 28,
        pointerEvents = "auto",
        onClick = function()
            if debugOverlay_ then
                M.Hide()
            else
                M.Show()
            end
        end,
    }
end

--- 创建一个调试按钮
local function DebugButton(label, onClick)
    return UI.Button {
        text = label,
        fontSize = 13,
        width = "100%",
        height = 36,
        variant = "outline",
        borderColor = { 100, 140, 220, 180 },
        fontColor = { 200, 210, 230, 255 },
        onClick = onClick,
    }
end

--- 显示 Debug 面板
function M.Show()
    if debugOverlay_ or not currentRoot_ then return end

    local IdleMode = require("IdleMode")

    debugOverlay_ = UI.Panel {
        id = "debugOverlay",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 120 },
        pointerEvents = "auto",
        onClick = function()
            M.Hide()
        end,
        children = {
            UI.Panel {
                width = 220,
                padding = 16,
                borderRadius = 12,
                backgroundColor = { 30, 35, 55, 240 },
                borderColor = { 80, 120, 200, 120 },
                borderWidth = 1,
                gap = 10,
                alignItems = "center",
                -- 阻止点击穿透关闭
                pointerEvents = "auto",
                onClick = function() end,
                children = {
                    UI.Label {
                        text = "Debug 面板",
                        fontSize = 16,
                        fontColor = { 220, 180, 80, 255 },
                        marginBottom = 4,
                    },
                    DebugButton("解锁下一关", function()
                        M.Hide()
                        -- 走正常的技能选择流程：弹出三选一面板，由 ApplySkillChoice 推进关卡
                        local choices = IdleMode.RollSkillChoices()
                        if #choices > 0 then
                            local IdleUI = require("IdleUI")
                            IdleUI.ShowSkillPickPopup(choices, function(skillId)
                                IdleMode.ApplySkillChoice(skillId)
                                IdleUI.RefreshCurrentTab()
                            end)
                            print("[Debug] Triggered skill pick popup for next level")
                        else
                            -- 无技能可选时直接推进（兜底）
                            local nextLevel = gameState.idleLevel + 1
                            gameState.idleMaxUnlockedLevel = math.max(gameState.idleMaxUnlockedLevel, nextLevel)
                            gameState.idleSkillPickCount = gameState.idleSkillPickCount + 1
                            gameState.idleBallAbilityLevels = {}
                            IdleMode.SwitchToLevel(nextLevel)
                            State.uiDirty = true
                            local IdleUI = require("IdleUI")
                            IdleUI.RefreshCurrentTab()
                            local SaveSystem = require("SaveSystem")
                            SaveSystem.Save()
                            print("[Debug] No skills available, directly unlocked level " .. nextLevel)
                        end
                    end),
                    DebugButton("+10K 球币", function()
                        gameState.idleBallCoins = gameState.idleBallCoins + BigNum.new(10000)
                        State.uiDirty = true
                        M.Hide()
                        local IdleUI = require("IdleUI")
                        IdleUI.RefreshCurrentTab()
                        print("[Debug] +10K ball coins")
                    end),
                    DebugButton("+10K 金币", function()
                        gameState.idleCoins = gameState.idleCoins + BigNum.new(10000)
                        State.uiDirty = true
                        M.Hide()
                        local IdleUI = require("IdleUI")
                        IdleUI.RefreshCurrentTab()
                        print("[Debug] +10K gold coins")
                    end),
                    DebugButton("清除放置存档", function()
                        -- 重置所有放置模式持久化字段
                        gameState.idleCoins = BigNum.new(0)
                        gameState.idleBallCoins = BigNum.new(0)
                        gameState.idleTotalEarned = BigNum.new(0)
                        gameState.idleTotalBallCoins = BigNum.new(0)
                        gameState.idleBallLevels = { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
                        gameState.idleSelectedBall = 1
                        gameState.idleSlots = {}
                        gameState.idleDrawnEffects = {}
                        gameState.idleDrawCount = 0
                        gameState.idleDrawPity = 0
                        gameState.idlePrestigeCount = 0
                        gameState.idlePrestigeMult = 1.0
                        gameState.idleLevel = 1
                        gameState.idleMaxUnlockedLevel = 1
                        gameState.idleBallsDropped = 0
                        gameState.idleGlobalBallValueBonus = 0
                        gameState.idleGlobalSlotMultBonus = 0
                        gameState.idleUpgradeLevels = {}
                        gameState.idleBallAbilityLevels = {}
                        gameState.idleLevelData = {}
                        gameState.idleSkills = {}
                        gameState.idleSkillPickCount = 0
                        -- 保存并重新进入放置模式
                        local SaveSystem = require("SaveSystem")
                        SaveSystem.Save()
                        M.Hide()
                        -- 重新进入放置模式（重建 UI 和棋盘）
                        IdleMode.Exit()
                        IdleMode.Enter()
                        print("[Debug] Idle save cleared, re-entered idle mode")
                    end),
                    DebugButton("关闭", function()
                        M.Hide()
                    end),
                },
            },
        },
    }

    currentRoot_:AddChild(debugOverlay_)
end

--- 隐藏 Debug 面板
function M.Hide()
    if debugOverlay_ then
        debugOverlay_:Remove()
        debugOverlay_ = nil
    end
end

return M
