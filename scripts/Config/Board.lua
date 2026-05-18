-- ============================================================================
-- Config/Board.lua - 弹珠台布局与物理配置
-- ============================================================================

local M = {}

M.CONFIG = {
    Title = "疯狂弹珠",

    BOARD_MARGIN_TOP = 60,
    BOARD_SPLIT_RATIO = 0.52,
    BOARD_PADDING_X = 0,

    PEG_ROWS = 9,
    PEG_RADIUS = 4,
    PEG_COLOR = { 180, 200, 220, 255 },
    PEG_HIT_COLOR = { 255, 220, 100, 255 },
    PEG_HIT_DURATION = 0.3,

    GRAVITY = 600,
    BOUNCE_DAMPING = 0.6,
    BALL_RADIUS = 4.5,

    MAX_BALLS = 50,
    RANDOM_NUDGE = 40,

    MAX_SLOTS = 5,
    SLOT_HEIGHT = 40,

    -- 内容区域边距（相对于 board 边界向内缩进，放撞钉和口袋）
    CONTENT_MARGIN_X = 10,
    CONTENT_MARGIN_TOP = 8,
    CONTENT_MARGIN_BOT = 0,

    -- 口袋分隔线位置（占图片宽度的比例，从图片实际测量）
    -- 图片内壁：左 0.024, 右 0.9768
    -- 4 条分隔线：0.2713, 0.4291, 0.5722, 0.7297
    SLOT_DIVIDERS = { 0.2713, 0.4291, 0.5722, 0.7297 },
    SLOT_INNER_LEFT  = 0.024,
    SLOT_INNER_RIGHT = 0.9768,

    DIVIDER_WIDTH = 3,
    DIVIDER_HEIGHT = 50,
    DIVIDER_COLOR = { 140, 160, 200, 230 },
    DIVIDER_GLOW_COLOR = { 180, 200, 240, 80 },

    POPUP_DURATION = 1.2,
    POPUP_RISE = 50,
}

-- 好坑倍率池
M.GOOD_MULT_POOL = { 1, 1, 2, 2, 3, 5, 10 }

-- 口袋倍率：无限升级，等级 N 对应倍率 = floor(1.3^(N-1))，至少为 N
---@param level number 口袋等级（>=1）
---@return number 倍率值
function M.GetSlotMult(level)
    if level <= 1 then return 1 end
    return math.max(level, math.floor(1.3 ^ (level - 1)))
end

local BigNum = require("BigNum")

--- 计算口袋升级费用（从当前等级升到下一级）
---@param level number 当前等级（>=1）
---@return table BigNum 升级费用
function M.GetSlotUpgradeCost(level)
    return math.floor(BigNum.new(40) * BigNum.new(1.6) ^ (level - 1))
end

local multColorCache = {}
local MULT_COLOR_1 = { 100, 115, 140, 255 }

--- 根据倍率值生成颜色（连续渐变，支持任意倍率）
---@param mult number
---@return table {r,g,b,a}
function M.GetMultColor(mult)
    if mult <= 1 then return MULT_COLOR_1 end
    local cached = multColorCache[mult]
    if cached then return cached end
    local t = math.log(mult) / math.log(2)
    local phase = t * 0.8
    local r = math.floor(128 + 127 * math.sin(phase))
    local g = math.floor(128 + 127 * math.sin(phase + 2.094))
    local b = math.floor(128 + 127 * math.sin(phase + 4.189))
    local bright = math.min(1.3, 1.0 + t * 0.02)
    r = math.min(255, math.floor(r * bright))
    g = math.min(255, math.floor(g * bright))
    b = math.min(255, math.floor(b * bright))
    local color = { r, g, b, 255 }
    multColorCache[mult] = color
    return color
end

return M
