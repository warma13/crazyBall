-- ============================================================================
-- IdleUI.lua - 放置模式 UI 协调器
-- 管理放置模式下半屏的 UI 组件生命周期，
-- 委托给 UI/IdleBallPanel、UI/IdleSlotPanel、UI/IdlePrestigePanel 子模块。
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local State = require("State")

local IdleBallPanel    = require("UI.IdleBallPanel")
local IdleSkillPanel   = require("UI.IdleSkillPanel")
local IdlePrestigePanel = require("UI.IdlePrestigePanel")
local IdleUpgradePanel = require("UI.IdleUpgradePanel")
-- local DropButton    = require("UI.DropButton")  -- 已改用图片版

local DebugPanel       = require("UI.DebugPanel")

local CONFIG   = Config.CONFIG
local gameState = State.gameState

local M = {}

-- NanoVG 进度环数据（供 IdleMode.DrawDropRing 读取）
M.dropRingProgress = 1  -- 0~1，1 表示就绪

-- UI 背景图路径
local IMG = {
    TAB_ACTIVE = "image/ui_tab_active_20260517160019.png",
    PANEL_BG   = "image/ui_panel_bg_v3_20260518184142.png",
    BOTTOM_BAR = "image/ui_bottom_bar_20260517184541.png",
}
local TAB_SLICE   = { top = 12, right = 12, bottom = 12, left = 12 }
local PANEL_SLICE = { top = 30, right = 30, bottom = 30, left = 30 }
local BAR_SLICE   = { top = 10, right = 20, bottom = 10, left = 20 }

-- 内部状态
local idleRoot_     = nil   -- 放置模式 UI 根节点
local dropBtn_      = nil   -- 掉落按钮引用
local activeTab     = "balls"   -- "balls" | "skills" | "prestige"
local tabScrollY    = { balls = 0, skills = 0, prestige = 0, upgrade = 0 }
local pendingRestore = nil  -- { tab, y, frames }

-- affordability 缓存
local lastAffordKey = ""

-- ============================================================================
-- 回调表（cb）——子模块通过闭包访问 IdleMode 的方法
-- ============================================================================

local function PlayClickSfx()
    if State.sfxButtonClick then
        local vol = gameState.settings and gameState.settings.sfxVolume or 1
        if vol > 0 and State.sfxScene_ then
            local node = State.sfxScene_:CreateChild("SFX")
            local src = node:CreateComponent("SoundSource")
            src.soundType = "Effect"
            src.gain = 0.4 * vol
            src.autoRemoveMode = REMOVE_NODE
            src:Play(State.sfxButtonClick)
        end
    end
end

local cb = {
    PlayClickSfx = PlayClickSfx,
    ADS_ENABLED  = true,

    -- IdleMode 方法（延迟绑定，避免循环依赖）
    PurchaseBallAbility = function(abilityId)
        local IdleMode = require("IdleMode")
        if IdleMode.PurchaseBallAbility(abilityId) then
            M.RefreshCurrentTab()  -- 立即重建 UI，防止连点用旧按钮重复升级
        end
    end,
    -- 口袋升级已改为自动（掉球N个+1倍率），无需手动回调
    DoPrestige = function()
        local IdleMode = require("IdleMode")
        if IdleMode.DoPrestige() then
            activeTab = "balls"
            M.RefreshCurrentTab()
        end
    end,
    CanPrestige = function()
        local IdleMode = require("IdleMode")
        return IdleMode.CanPrestige()
    end,
    PurchaseUpgrade = function(upgradeId)
        local IdleMode = require("IdleMode")
        if IdleMode.PurchaseUpgrade(upgradeId) then
            M.RefreshCurrentTab()
        end
    end,
    PurchasePrestigeAbility = function(abilityId)
        local IdleMode = require("IdleMode")
        if IdleMode.PurchasePrestigeAbility(abilityId) then
            M.RefreshCurrentTab()
        end
    end,
}

-- ============================================================================
-- Tab Content
-- ============================================================================

local function CreateTabContent()
    if activeTab == "balls" then
        return IdleBallPanel.CreateBallList(cb)
    elseif activeTab == "skills" then
        return IdleSkillPanel.CreateSkillList(cb)
    elseif activeTab == "prestige" then
        return IdlePrestigePanel.CreatePrestigePanel(cb)
    elseif activeTab == "upgrade" then
        return IdleUpgradePanel.CreateUpgradeList(cb)
    end
    return UI.Panel {}
end

-- ============================================================================
-- Tab Bar
-- ============================================================================

-- 激活态底部径向高光（小范围居中）
local TAB_GLOW_ACTIVE = {
    type = "radial",
    cx = 0.5, cy = 0.7,
    radius = 0.45,
    from = { 60, 140, 255, 100 },
    to   = { 60, 140, 255, 0 },
}

local function CreateTabButton(label, tabKey)
    local isActive = (activeTab == tabKey)
    local cfg = {
        id = "idleTab_" .. tabKey,
        flexGrow = 1, flexBasis = 0,
        height = "100%",
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        onClick = function()
            PlayClickSfx()
            if activeTab ~= tabKey then
                M.SaveTabScroll()
                activeTab = tabKey
                lastAffordKey = ""
                M.RefreshTabContent()
                M.UpdateTabBar()
                M.RestoreTabScroll()
            end
        end,
        children = {
            UI.Label {
                id = "idleTabLabel_" .. tabKey,
                text = label,
                fontSize = 14,
                fontColor = isActive
                    and { 180, 210, 255, 255 }
                    or { 100, 110, 140, 200 },
                textAlign = "center",
            },
        },
    }
    if isActive then
        cfg.backgroundGradient = TAB_GLOW_ACTIVE
    end
    return UI.Panel(cfg)
end

--- 创建底部栏中间的掉落按钮（图片版：边框 + 球体，进度环由 NanoVG 绘制）
local function CreateCenterDropButton()
    local btnSize = 68
    local isCooling = false

    -- 球体图片
    local ballImg = UI.Panel {
        id = "dropBallImg",
        position = "absolute",
        top = 13, left = 13, right = 13, bottom = 11,
        backgroundImage = "image/ui_drop_ball_20260517191044.png",
        backgroundFit = "contain",
        pointerEvents = "none",
        transition = "scale 0.15s easeOut, opacity 0.1s easeOut",
    }

    -- 边框按钮
    local frameImg = UI.Panel {
        id = "dropFrameImg",
        width = btnSize,
        height = btnSize,
        backgroundImage = "image/ui_drop_frame_20260518063812.png",
        backgroundFit = "contain",
        pointerEvents = "auto",
        onPointerDown = function(event, widget)
            if isCooling then return end
            ballImg:SetStyle({ scale = 0.85, opacity = 0.8 })
        end,
        onPointerUp = function(event, widget)
            ballImg:SetStyle({ scale = 1.0, opacity = isCooling and 0.55 or 1.0 })
        end,
        onPointerLeave = function(event, widget)
            ballImg:SetStyle({ scale = 1.0, opacity = isCooling and 0.55 or 1.0 })
        end,
        onClick = function()
            if isCooling then return end
            PlayClickSfx()
            local IdleMode = require("IdleMode")
            IdleMode.DropBall(nil)
        end,
        children = { ballImg },
    }

    -- 冷却更新：控制球体暗淡 + 弹跳 + 暴露进度给 NanoVG 绘制
    local wasCooling = false

    function frameImg:UpdateCooldown(progress)
        progress = math.max(0, math.min(1, progress or 1))
        local nowCooling = progress < 1

        -- 更新 NanoVG 进度环数据
        M.dropRingProgress = progress

        if nowCooling then
            if not wasCooling then
                ballImg:SetStyle({ opacity = 0.55 })
            end
        else
            if wasCooling then
                ballImg:SetStyle({ opacity = 1.0, scale = 1.15 })
                ballImg:SetStyle({ scale = 1.0 })
            end
        end

        wasCooling = nowCooling
        isCooling = nowCooling
    end

    dropBtn_ = frameImg

    return UI.Panel {
        id = "idleTab_drop",
        flexGrow = 1.2, flexBasis = 0,
        height = "100%",
        flexDirection = "column",
        justifyContent = "flex-end",
        alignItems = "center",
        overflow = "visible",
        pointerEvents = "auto",
        children = {
            UI.Panel {
                overflow = "visible",
                marginBottom = 2,
                marginTop = -32,
                children = { frameImg },
            },
            UI.Label {
                text = "投放",
                fontSize = 12,
                fontColor = { 160, 185, 220, 220 },
                textAlign = "center",
                marginBottom = 2,
            },
        },
    }
end

local function CreateBottomBar()
    return UI.Panel {
        id = "idleBottomBar",
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        height = 56,
        overflow = "visible",
        backgroundImage = IMG.BOTTOM_BAR,
        backgroundFit = "cover",
        children = {
            CreateTabButton("弹珠", "balls"),
            CreateTabButton("技能", "skills"),
            CreateCenterDropButton(),
            CreateTabButton("升级", "upgrade"),
            CreateTabButton("转生", "prestige"),
        },
    }
end

-- ============================================================================
-- Upgrade Panel (下半屏)
-- ============================================================================



--- 创建当前 tab 的固定 header（不滚动）
local function CreateTabHeader()
    if activeTab == "balls" then
        return IdleBallPanel.CreateBallHeader()
    elseif activeTab == "skills" then
        return IdleSkillPanel.CreateSkillHeader()
    elseif activeTab == "upgrade" then
        return IdleUpgradePanel.CreateUpgradeHeader()
    end
    return nil
end

local function CreateUpgradePanel()
    local headerChildren = {}
    local hdr = CreateTabHeader()
    if hdr then headerChildren[1] = hdr end

    -- 动态计算切片边距和内边距（与主游戏 GameUI 一致）
    local ps = math.floor(30 * 320 / State.refWidth)

    return UI.Panel {
        id = "idleUpgradePanel",
        width = "100%",
        flexGrow = 1,
        backgroundImage = IMG.PANEL_BG,
        backgroundFit = "sliced",
        backgroundSlice = { top = ps, right = ps, bottom = ps, left = ps },
        padding = { ps, ps, math.floor(ps * 0.8), ps },
        overflow = "hidden",
        children = {
            -- 固定 header 容器
            UI.Panel {
                id = "idleTabHeader",
                width = "100%",
                children = headerChildren,
            },
            UI.ScrollView {
                id = "idleTabContent",
                width = "100%",
                flexGrow = 1,
                showScrollbar = false,
                padding = { 2, 2, 2, 2 },
                onScroll = function(self, sx, sy)
                    if not pendingRestore then
                        tabScrollY[activeTab] = sy
                    end
                end,
                children = { CreateTabContent() },
            },
            CreateBottomBar(),
        },
    }
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 创建放置模式 UI（进入放置模式时调用）
function M.CreateUI()
    local splitPct = math.floor(CONFIG.BOARD_SPLIT_RATIO * 100) .. "%"
    local Renderer = require("Renderer")

    idleRoot_ = UI.SafeAreaView {
        id = "idleRoot",
        width = "100%",
        height = "100%",
        edges = { "top" },
        mode = "padding",
        pointerEvents = "box-none",
        children = {
            -- 上半屏占位（NanoVG 棋盘区域）
            UI.Panel {
                width = "100%",
                height = splitPct,
                pointerEvents = "none",
            },
            -- 下半屏升级面板
            CreateUpgradePanel(),
            -- 左下角版本号（绝对定位，浮于 UI 最上层）
            UI.Label {
                position = "absolute",
                bottom = 4, left = 4,
                text = Renderer.GAME_VERSION,
                fontSize = 9,
                fontColor = { 180, 190, 210, 100 },
                pointerEvents = "none",
            },
            -- 右上角 Debug 触发区域（覆盖在用户ID上方）
            DebugPanel.CreateDebugTrigger(),
        },
    }

    DebugPanel.SetRoot(idleRoot_)

    activeTab = "balls"
    tabScrollY = { balls = 0, skills = 0, prestige = 0, upgrade = 0 }
    lastAffordKey = ""
    pendingRestore = nil

    UI.SetRoot(idleRoot_)

    -- 注册全局渲染组件：在 UI 层之上绘制掉落按钮进度环
    UI.RegisterGlobalComponent("dropRing", {
        Render = function(self, nvg)
            M.RenderDropRing(nvg)
        end
    })

    print("[IdleUI] UI created")
end

--- 销毁放置模式 UI（退出放置模式时调用）
function M.DestroyUI()
    if idleRoot_ then
        UI.UnregisterGlobalComponent("dropRing")
        UI.SetRoot(nil)
        idleRoot_ = nil
        dropBtn_ = nil
        print("[IdleUI] UI destroyed")
    end
end

--- 在 UI 层之上绘制掉落按钮的圆弧进度环（由 GlobalComponent 回调）
--- @param nvg userdata UI 库的 NanoVG 上下文
function M.RenderDropRing(nvg)
    if not dropBtn_ then return end
    local progress = M.dropRingProgress
    if not progress then return end

    -- 获取按钮的屏幕绝对坐标（UI base pixels）
    local layout = dropBtn_:GetAbsoluteLayout()
    local cx = layout.x + layout.w / 2
    local cy = layout.y + layout.h / 2

    -- 球体外发光（径向渐变光晕）
    local glowRadius = math.min(layout.w, layout.h) / 2 - 8
    local glowPaint = nvgRadialGradient(nvg, cx, cy, glowRadius * 0.3, glowRadius,
        nvgRGBA(100, 180, 255, 60), nvgRGBA(100, 180, 255, 0))
    nvgBeginPath(nvg)
    nvgCircle(nvg, cx, cy, glowRadius)
    nvgFillPaint(nvg, glowPaint)
    nvgFill(nvg)

    local ringRadius = math.min(layout.w, layout.h) / 2 - 3  -- 紧贴底座边缘内侧
    local ringWidth  = 3

    -- 起始角度：12 点钟位置（-π/2），顺时针扫过
    local startAngle = -math.pi / 2
    local endAngle   = startAngle + progress * math.pi * 2

    -- 底色轨道（暗色完整圆环）
    nvgBeginPath(nvg)
    nvgArc(nvg, cx, cy, ringRadius, 0, math.pi * 2, NVG_CW)
    nvgStrokeColor(nvg, nvgRGBA(35, 40, 55, 180))
    nvgStrokeWidth(nvg, ringWidth)
    nvgStroke(nvg)

    -- 进度弧线（亮色，从12点钟顺时针到当前进度）
    if progress > 0.005 then
        nvgBeginPath(nvg)
        nvgArc(nvg, cx, cy, ringRadius, startAngle, endAngle, NVG_CW)
        nvgStrokeColor(nvg, nvgRGBA(80, 170, 255, 230))
        nvgStrokeWidth(nvg, ringWidth)
        nvgLineCap(nvg, NVG_ROUND)
        nvgStroke(nvg)
    end
end

--- 每帧更新（scroll 恢复）
function M.Update(dt)
    if not idleRoot_ then return end

    if pendingRestore then
        local sv = idleRoot_:FindById("idleTabContent")
        if sv and activeTab == pendingRestore.tab then
            sv.state.scrollY = pendingRestore.y
            sv.state.velocityY = 0
        end
        pendingRestore.frames = pendingRestore.frames - 1
        if pendingRestore.frames <= 0 then
            pendingRestore = nil
        end
    end

    -- 更新掉落按钮冷却进度
    if dropBtn_ then
        local IdleMode = require("IdleMode")
        local progress = IdleMode.GetDropCooldownProgress()
        dropBtn_:UpdateCooldown(progress)
    end

    -- 更新技能面板 CD 状态（在技能页时实时刷新）
    if activeTab == "skills" then
        IdleSkillPanel.UpdateSkillItems()
    end

    -- 定时检查 affordability 变化
    M.CheckAffordRefresh()
end

-- ============================================================================
-- 局部刷新
-- ============================================================================

--- 刷新当前 tab 的全部内容
function M.RefreshCurrentTab()
    lastAffordKey = ""
    M.RefreshTabContent()
end

--- 重建 tab 内容区（含固定 header）
function M.RefreshTabContent()
    if not idleRoot_ then return end
    -- 刷新固定 header
    local hdrContainer = idleRoot_:FindById("idleTabHeader")
    if hdrContainer then
        hdrContainer:ClearChildren()
        local hdr = CreateTabHeader()
        if hdr then hdrContainer:AddChild(hdr) end
    end
    -- 刷新滚动内容
    local sv = idleRoot_:FindById("idleTabContent")
    if sv then
        sv:ClearChildren()
        sv:AddChild(CreateTabContent())
    end
end

--- 更新 tab bar 高亮
function M.UpdateTabBar()
    if not idleRoot_ then return end
    local tabs = { "balls", "skills", "upgrade", "prestige" }
    for _, key in ipairs(tabs) do
        local isActive = (activeTab == key)
        local tabBtn = idleRoot_:FindById("idleTab_" .. key)
        if tabBtn then
            tabBtn:SetStyle({
                backgroundGradient = isActive and TAB_GLOW_ACTIVE or "none",
            })
        end
        local tabLabel = idleRoot_:FindById("idleTabLabel_" .. key)
        if tabLabel then
            tabLabel:SetStyle({
                fontColor = isActive
                    and { 180, 210, 255, 255 }
                    or { 100, 110, 140, 200 },
            })
        end
    end
end

--- 保存当前 tab 的滚动位置
function M.SaveTabScroll()
    if not idleRoot_ then return end
    local sv = idleRoot_:FindById("idleTabContent")
    if sv then
        local _, sy = sv:GetScroll()
        tabScrollY[activeTab] = sy or 0
    end
end

--- 恢复 tab 的滚动位置
function M.RestoreTabScroll()
    local y = tabScrollY[activeTab] or 0
    pendingRestore = { tab = activeTab, y = y, frames = 4 }
    if idleRoot_ then
        local sv = idleRoot_:FindById("idleTabContent")
        if sv then
            sv:SetScrollDirect(0, y)
            sv.state.velocityY = 0
        end
    end
end

--- 检查 affordability 变化，轻量更新样式；仅等级/结构变化时全量重建
function M.CheckAffordRefresh()
    -- 先轻量更新 header 货币数字（每帧开销极小）
    if activeTab == "balls" then
        IdleBallPanel.UpdateHeader(idleRoot_)
    elseif activeTab == "upgrade" then
        IdleUpgradePanel.UpdateHeader(idleRoot_)
    end

    -- 尝试轻量更新 canAfford 样式
    if activeTab == "balls" then
        IdleBallPanel.UpdateAfford(idleRoot_)
    elseif activeTab == "upgrade" then
        IdleUpgradePanel.UpdateAfford(idleRoot_)
    end

    -- 结构性变化（等级改变等）仍需全量重建
    local key = M.ComputeStructKey()
    if key ~= lastAffordKey then
        lastAffordKey = key
        M.RefreshTabContent()
    end
end

--- 计算结构性 key（只包含等级/解锁等结构数据，不含 coin 值和 canAfford）
function M.ComputeStructKey()
    local IdleMode = require("IdleMode")
    if activeTab == "balls" then
        local ballUpgrades = IdleMode.GetCurrentBallUpgrades()
        local bits = {}
        for i, abCfg in ipairs(ballUpgrades) do
            local lv = IdleMode.GetBallAbilityLevel(abCfg.id)
            bits[i] = tostring(lv)
        end
        return "B" .. gameState.idleLevel .. "_" .. table.concat(bits, "_")
    elseif activeTab == "skills" then
        local bits = {}
        for id, lv in pairs(gameState.idleSkills) do
            bits[#bits + 1] = id .. lv
        end
        table.sort(bits)
        return "K" .. gameState.idleLevel .. "_" .. gameState.idleSkillPickCount .. "_" .. table.concat(bits, "_")
    elseif activeTab == "prestige" then
        local can = IdleMode.CanPrestige() and "1" or "0"
        local abBits = {}
        for _, cfg in ipairs(Config.IDLE.PRESTIGE_ABILITIES) do
            local lv = IdleMode.GetPrestigeAbilityLevel(cfg.id)
            abBits[#abBits + 1] = tostring(lv)
        end
        return "P" .. can .. "_" .. gameState.idlePrestigeCount .. "_" .. gameState.idleStardust .. "_" .. table.concat(abBits, "_")
    elseif activeTab == "upgrade" then
        local bits = {}
        for i, upgCfg in ipairs(Config.IDLE.UPGRADES) do
            local lv = gameState.idleUpgradeLevels[upgCfg.id] or 0
            bits[i] = tostring(lv)
        end
        return "U" .. table.concat(bits, "_")
    end
    return ""
end

-- ============================================================================
-- 技能三选一弹窗
-- ============================================================================

local skillPopup_ = nil  -- 弹窗引用

--- 显示技能三选一弹窗
---@param choices table[] 可选技能配置列表
---@param onPick function(skillId) 选择回调
function M.ShowSkillPickPopup(choices, onPick)
    if not idleRoot_ then return end
    M.HideSkillPickPopup()  -- 先清理旧弹窗

    skillPopup_ = IdleSkillPanel.CreateSkillPickPopup(choices, function(skillId)
        M.HideSkillPickPopup()
        if onPick then onPick(skillId) end
    end)

    idleRoot_:AddChild(skillPopup_)
end

--- 隐藏技能弹窗
function M.HideSkillPickPopup()
    if skillPopup_ then
        skillPopup_:Remove()
        skillPopup_ = nil
    end
end

--- 获取放置模式 UI 根节点（供子面板添加覆盖层）
function M.GetRoot()
    return idleRoot_
end

return M
