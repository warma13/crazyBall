-- ============================================================================
-- UI/SettingsPanel.lua - 设置弹窗面板
-- ============================================================================

local UI = require("urhox-libs/UI")
local State = require("State")

local CONFIG = require("Config").CONFIG
local gameState = State.gameState

local P = {}

--- 创建按钮（设置面板内部用）
local function CreateSettingsButton(cb, text, color, borderColor, onClick)
    return UI.Panel {
        width = "80%",
        padding = { 14, 12, 14, 12 },
        backgroundColor = color,
        borderColor = borderColor,
        borderWidth = 1.5, borderRadius = 10,
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto",
        onClick = function()
            cb.PlayClickSfx()
            if onClick then onClick() end
        end,
        children = {
            UI.Label {
                text = text,
                fontSize = 18,
                fontColor = { 255, 255, 255, 240 },
                textAlign = "center",
            },
        }
    }
end

--- 创建设置行：标签 + 右侧控件
local function CreateSettingsRow(label, rightChild)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        padding = { 4, 6, 4, 6 },
        children = {
            UI.Label {
                text = label,
                fontSize = 17,
                fontColor = { 200, 210, 230, 240 },
                flexShrink = 0,
                marginRight = 8,
            },
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                alignItems = "flex-end",
                children = { rightChild },
            },
        }
    }
end

--- 创建开关控件（模拟 Toggle）
local function CreateToggle(cb, isOn, onToggle)
    local bgColor = isOn and { 60, 160, 90, 240 } or { 60, 65, 85, 240 }
    local dotAlign = isOn and "flex-end" or "flex-start"
    return UI.Panel {
        width = 48, height = 26, borderRadius = 13,
        backgroundColor = bgColor,
        borderColor = isOn and { 80, 200, 120, 200 } or { 80, 85, 110, 200 },
        borderWidth = 1.5,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = dotAlign,
        padding = { 0, 3, 0, 3 },
        pointerEvents = "auto",
        onClick = function()
            cb.PlayClickSfx()
            if onToggle then onToggle() end
        end,
        children = {
            UI.Panel {
                width = 20, height = 20, borderRadius = 10,
                backgroundColor = { 255, 255, 255, 240 },
                pointerEvents = "none",
            },
        }
    }
end

--- 创建设置面板
---@param cb table 回调表 { PlayClickSfx, HideSettingsPanel, ShowSettingsPanel }
---@return table UI 面板
function P.CreateSettingsPanel(cb)
    local SaveSystem = require("SaveSystem")
    local settings = gameState.settings

    return UI.Panel {
        id = "settingsOverlay",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = { 0, 0, 0, 160 },
        pointerEvents = "auto",
        onClick = function()
            cb.PlayClickSfx()
            cb.HideSettingsPanel()
        end,
        children = {
            UI.Panel {
                width = "80%",
                backgroundColor = { 20, 25, 50, 245 },
                borderColor = { 80, 110, 180, 200 },
                borderWidth = 2, borderRadius = 12,
                padding = { 16, 20, 16, 20 },
                alignItems = "center",
                pointerEvents = "auto",
                onClick = function() end,  -- 阻止穿透
                children = {
                    -- 右上角关闭
                    UI.Panel {
                        position = "absolute",
                        top = 6, right = 8,
                        width = 26, height = 26, borderRadius = 13,
                        backgroundColor = { 50, 55, 80, 200 },
                        justifyContent = "center", alignItems = "center",
                        pointerEvents = "auto",
                        onClick = function()
                            cb.PlayClickSfx()
                            cb.HideSettingsPanel()
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
                    -- 标题
                    UI.Label {
                        text = "设置",
                        fontSize = 23,
                        fontColor = { 255, 255, 255, 240 },
                        textAlign = "center",
                        marginBottom = 16,
                    },

                    -- ==== 音效音量 ====
                    CreateSettingsRow("音效音量", UI.Slider {
                        id = "sfxSlider",
                        width = 140, height = 24,
                        min = 0, max = 100,
                        value = math.floor(settings.sfxVolume * 100),
                        onChange = function(self, value)
                            settings.sfxVolume = value / 100
                            State.ApplyAudioSettings()
                        end,
                    }),

                    -- ==== 音乐音量 ====
                    CreateSettingsRow("音乐音量", UI.Slider {
                        id = "musicSlider",
                        width = 140, height = 24,
                        min = 0, max = 100,
                        value = math.floor(settings.musicVolume * 100),
                        onChange = function(self, value)
                            settings.musicVolume = value / 100
                            State.ApplyAudioSettings()
                        end,
                    }),

                    -- ==== 震屏开关 ====
                    CreateSettingsRow("震屏效果",
                        CreateToggle(cb, settings.shakeEnabled, function()
                            settings.shakeEnabled = not settings.shakeEnabled
                            -- 重建面板以刷新 Toggle 样式
                            cb.ShowSettingsPanel()
                        end)
                    ),

                    -- 分隔线
                    UI.Panel {
                        width = "90%", height = 1,
                        backgroundColor = { 60, 70, 100, 150 },
                        marginTop = 12, marginBottom = 12,
                    },

                    -- 保存按钮
                    CreateSettingsButton(cb,
                        "保存游戏",
                        { 40, 70, 55, 240 },
                        { 80, 180, 100, 200 },
                        function()
                            local ok = SaveSystem.SaveLocal()
                            SaveSystem.Flush()
                            cb.HideSettingsPanel()
                            if ok then
                                gameState.failedToast = { timer = 1.5, text = "保存成功", offsetY = 0 }
                            else
                                gameState.failedToast = { timer = 1.5, text = "保存失败", offsetY = 0 }
                            end
                        end
                    ),

                    -- 间距
                    UI.Panel { width = "100%", height = 10 },

                    -- 返回主菜单按钮
                    CreateSettingsButton(cb,
                        "返回主菜单",
                        { 80, 35, 35, 240 },
                        { 200, 80, 80, 200 },
                        function()
                            SaveSystem.Save()
                            SaveSystem.Flush()
                            cb.HideSettingsPanel()
                            gameState.gamePhase = "menu"
                            gameState.roundPhase = "playing"
                            gameState.paused = false
                            -- 清理 UI
                            if State.uiRoot_ then
                                State.uiRoot_:ClearChildren()
                                State.uiRoot_ = nil
                            end
                        end
                    ),
                }
            },
        }
    }
end

return P
