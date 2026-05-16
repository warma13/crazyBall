-- ============================================================================
-- EventBus.lua - 轻量发布/订阅
-- ============================================================================

local M = {}

---@type table<string, function[]>
local listeners = {}

--- 订阅事件
---@param event string
---@param callback function
function M.on(event, callback)
    if not listeners[event] then
        listeners[event] = {}
    end
    table.insert(listeners[event], callback)
end

--- 发布事件
---@param event string
---@param data any
function M.emit(event, data)
    if not listeners[event] then return end
    for _, cb in ipairs(listeners[event]) do
        cb(data)
    end
end

return M
