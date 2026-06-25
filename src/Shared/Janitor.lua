-- Janitor: a minimal cleanup helper (no framework). Track connections, instances, and cleanup
-- functions; drop them all with one :cleanup() call. Used so per-player / per-effect / tutorial
-- connections and temporary instances are released deterministically on leave/finish instead of
-- leaking across join/leave/steal/death cycles.
--
-- Intentionally tiny: add() returns what you pass so you can inline it.

local Janitor = {}
Janitor.__index = Janitor

function Janitor.new()
    return setmetatable({ _items = {} }, Janitor)
end

-- Track a RBXScriptConnection, an Instance, or a function (called on cleanup). Returns `item`.
function Janitor:add(item)
    table.insert(self._items, item)
    return item
end

-- Disconnects every connection, destroys every instance, and calls every function, in order,
-- then empties the list. Safe to call repeatedly.
function Janitor:cleanup()
    local items = self._items
    self._items = {}
    for _, item in ipairs(items) do
        if typeof(item) == "RBXScriptConnection" then
            item:Disconnect()
        elseif typeof(item) == "Instance" then
            item:Destroy()
        elseif type(item) == "function" then
            pcall(item)
        end
    end
end

return Janitor
