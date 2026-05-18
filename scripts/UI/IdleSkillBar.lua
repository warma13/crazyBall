-- ============================================================================
-- UI/IdleSkillBar.lua - CD 主动技能栏
-- 横排技能按钮，显示图标 + CD/Buff 状态，点击触发技能
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("Config")
local State = require("State")

local gameState = State.gameState

local M = {}

-- 内部引用
local barRoot_ = nil        -- 技能栏根节点
local skillBtns_ = {}       -- { [skillId] = { outer, iconLbl, cdLbl, overlay } }

-- ============================================================================
-- 配色
-- ============================================================================
local COLORS = {
    barBg         = { 12, 15, 30, 230 },
    barBorder     = { 50, 60, 90, 160 },
    -- 按钮
    btnReady      = { 50, 60, 100, 255 },
    btnActive     = { 40, 120, 80, 255 },
    btnCooling    = { 30, 30, 40, 220 },
    btnBorder     = { 80, 100, 160, 180 },
    btnActiveBdr  = { 60, 200, 120, 220 },
    -- CD 遮罩
    cdOverlay     = { 0, 0, 0, 160 },
    -- 文字
    iconReady     = { 255, 255, 255, 255 },
    iconCooling   = { 120, 120, 140, 180 },
    cdText        = { 255, 200, 80, 255 },
    buffText      = { 80, 255, 160, 255 },
    lvText        = { 180, 200, 240, 160 },
    emptyHint     = { 100, 110, 140, 120 },
}

local BTN_SIZE = 46
local BTN_GAP  = 6

-- ============================================================================
-- 内部：创建单个技能按钮
-- ============================================================================

---@param skillId string
---@param cfg table
---@param level number
---@param onActivate function(skillId)
local function CreateSkillButton(skillId, cfg, level, onActivate)
    local ic = cfg.iconColor or { 180, 180, 180 }
    local icon = cfg.icon or "?"

    -- CD 遮罩（覆盖整个按钮，高度从底部向上表示剩余 CD 比例）
    local cdOverlay = UI.Panel {
        id = "skillCD_" .. skillId,
        position = "absolute",
        left = 0, right = 0, bottom = 0,
        height = "0%",
        backgroundColor = COLORS.cdOverlay,
        borderRadius = 8,
        pointerEvents = "none",
    }

    -- 图标文字
    local iconLbl = UI.Label {
        id = "skillIcon_" .. skillId,
        text = icon,
        fontSize = 18,
        fontColor = COLORS.iconReady,
        textAlign = "center",
        pointerEvents = "none",
    }

    -- CD/Buff 倒计时文字
    local cdLbl = UI.Label {
        id = "skillCDLbl_" .. skillId,
        text = "",
        fontSize = 9,
        fontColor = COLORS.cdText,
        textAlign = "center",
        pointerEvents = "none",
    }

    -- 等级标签
    local lvLbl = UI.Label {
        id = "skillLv_" .. skillId,
        text = "Lv." .. level,
        fontSize = 8,
        fontColor = COLORS.lvText,
        textAlign = "center",
        position = "absolute",
        bottom = 1, right = 2,
        pointerEvents = "none",
    }

    local btn = UI.Panel {
        id = "skillBtn_" .. skillId,
        width = BTN_SIZE, height = BTN_SIZE,
        justifyContent = "center",
        alignItems = "center",
        borderRadius = 8,
        backgroundColor = COLORS.btnReady,
        borderColor = { ic[1], ic[2], ic[3], 160 },
        borderWidth = 1.5,
        pointerEvents = "auto",
        overflow = "hidden",
        onClick = function()
            if onActivate then onActivate(skillId) end
        end,
        children = {
            cdOverlay,
            iconLbl,
            cdLbl,
            lvLbl,
        },
    }

    skillBtns_[skillId] = {
        outer   = btn,
        iconLbl = iconLbl,
        cdLbl   = cdLbl,
        overlay = cdOverlay,
        lvLbl   = lvLbl,
        ic      = ic,
    }

    return btn
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 创建技能栏（返回 UI 面板，嵌入到 IdleUI 布局中）
---@param onActivate function(skillId) 技能激活回调
---@return table UI Panel
function M.Create(onActivate)
    skillBtns_ = {}

    -- 收集已获得的技能
    local skillItems = {}
    for _, cfg in ipairs(Config.IDLE.SKILLS) do
        local lv = gameState.idleSkills[cfg.id] or 0
        if lv > 0 then
            table.insert(skillItems, { cfg = cfg, level = lv })
        end
    end

    local children = {}

    if #skillItems == 0 then
        -- 无技能时显示提示
        table.insert(children, UI.Label {
            text = "获得技能后在此激活",
            fontSize = 11,
            fontColor = COLORS.emptyHint,
            textAlign = "center",
        })
    else
        for _, item in ipairs(skillItems) do
            table.insert(children, CreateSkillButton(
                item.cfg.id, item.cfg, item.level, onActivate
            ))
        end
    end

    barRoot_ = UI.Panel {
        id = "idleSkillBar",
        width = "100%",
        height = #skillItems > 0 and (BTN_SIZE + 12) or 28,
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        gap = BTN_GAP,
        backgroundColor = COLORS.barBg,
        borderColor = COLORS.barBorder,
        borderWidth = { 1, 0, 0, 0 },
        padding = { 0, 4, 0, 4 },
    }

    -- 手动添加 children（避免 table.unpack 位置问题）
    for _, child in ipairs(children) do
        barRoot_:AddChild(child)
    end

    return barRoot_
end

--- 每帧更新技能栏状态（CD/Buff 视觉）
function M.Update()
    if not barRoot_ then return end

    local IdleMode = require("IdleMode")
    local states = IdleMode.GetSkillStates()

    for _, st in ipairs(states) do
        local refs = skillBtns_[st.id]
        if refs then
            local cfg = st.cfg
            local ic = refs.ic

            if st.buffRemaining > 0 then
                -- Buff 激活中：绿色高亮
                refs.outer:SetStyle({
                    backgroundColor = COLORS.btnActive,
                    borderColor = COLORS.btnActiveBdr,
                })
                refs.iconLbl:SetStyle({ fontColor = { 220, 255, 220, 255 } })
                refs.cdLbl:SetStyle({
                    text = string.format("%.1fs", st.buffRemaining),
                    fontColor = COLORS.buffText,
                })
                -- 遮罩隐藏
                refs.overlay:SetStyle({ height = "0%" })

            elseif st.cdRemaining > 0 then
                -- 冷却中：灰色 + CD 遮罩
                local cdTotal = IdleMode.GetSkillCooldown(st.id)
                local cdPct = (cdTotal > 0) and (st.cdRemaining / cdTotal) or 0
                local heightPct = string.format("%.0f%%", cdPct * 100)

                refs.outer:SetStyle({
                    backgroundColor = COLORS.btnCooling,
                    borderColor = { ic[1], ic[2], ic[3], 60 },
                })
                refs.iconLbl:SetStyle({ fontColor = COLORS.iconCooling })
                refs.cdLbl:SetStyle({
                    text = string.format("%.0fs", math.ceil(st.cdRemaining)),
                    fontColor = COLORS.cdText,
                })
                refs.overlay:SetStyle({ height = heightPct })

            else
                -- 就绪：正常颜色
                refs.outer:SetStyle({
                    backgroundColor = COLORS.btnReady,
                    borderColor = { ic[1], ic[2], ic[3], 160 },
                })
                refs.iconLbl:SetStyle({ fontColor = COLORS.iconReady })
                refs.cdLbl:SetStyle({ text = "" })
                refs.overlay:SetStyle({ height = "0%" })
            end
        end
    end
end

--- 销毁（清理引用）
function M.Destroy()
    barRoot_ = nil
    skillBtns_ = {}
end

return M
