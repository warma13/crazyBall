-- ============================================================================
-- Config/Quality.lua - 品质系统与附魔系统
-- ============================================================================

local M = {}

-- ============================================================================
-- 品质系统
-- ============================================================================

M.QUALITY_TIERS = {
    common = { id = "common", name = "普通", color = { 180, 190, 210, 255 }, weight = 40 },
    rare   = { id = "rare",   name = "稀有", color = { 80, 160, 255, 255 },  weight = 30 },
    epic   = { id = "epic",   name = "精良", color = { 180, 80, 255, 255 },  weight = 18 },
    legend = { id = "legend", name = "史诗", color = { 255, 160, 40, 255 },  weight = 8 },
    mythic = { id = "mythic", name = "传说", color = { 255, 60, 60, 255 },   weight = 0 },
}

M.QUALITY_ORDER = { "mythic", "legend", "epic", "rare", "common" }

M.PITY_THRESHOLD = 20

---@param qualityId string
function M.GetQualityTier(qualityId)
    return M.QUALITY_TIERS[qualityId]
end

-- ============================================================================
-- 附魔系统（广告附魔，可叠加，重复升级）
-- ============================================================================

M.ENCHANTMENTS = {
    { id = "gem_chance",       name = "宝石猎手", icon = "\xF0\x9F\x92\x8E", color = { 180, 100, 255, 255 }, baseValue = 0.01, stacking = "add",
      descFunc = function(lv) return string.format("撞钉产宝石概率+%d%%", lv) end },
    { id = "peg_split",        name = "分裂之力", icon = "\xF0\x9F\x92\xA5", color = { 255, 120, 50, 255 },  baseValue = 0.05, stacking = "mul",
      descFunc = function(lv) local v = 1 - (1 - 0.05) ^ lv; return string.format("撞钉%.1f%%概率分裂球", v * 100) end },
    { id = "ball_value",       name = "点金术",   icon = "\xF0\x9F\x92\xB0", color = { 255, 220, 50, 255 },  baseValue = 1.00, stacking = "add",
      descFunc = function(lv) return string.format("球基础价值+%d%%", lv * 100) end },
    { id = "upgrade_discount", name = "精打细算", icon = "\xF0\x9F\x8F\xB7\xEF\xB8\x8F",  color = { 100, 200, 150, 255 }, baseValue = 0.05, stacking = "mul",
      descFunc = function(lv) local v = 1 - (1 - 0.05) ^ lv; return string.format("升级金币减少%.1f%%", v * 100) end },
    { id = "extra_ball",       name = "幸运投放", icon = "\xF0\x9F\x8E\xB2", color = { 80, 180, 255, 255 },  baseValue = 0.05, stacking = "add",
      descFunc = function(lv) return string.format("投放%d%%概率多一个球", lv * 5) end },
}

--- 根据 id 查找附魔配置（带缓存）
local _enchantCache = {}
function M.GetEnchantConfig(enchantId)
    if not enchantId then return nil end
    local cached = _enchantCache[enchantId]
    if cached ~= nil then return cached end
    for _, e in ipairs(M.ENCHANTMENTS) do
        if e.id == enchantId then
            _enchantCache[e.id] = e
            return e
        end
    end
    _enchantCache[enchantId] = false
    return nil
end

return M
