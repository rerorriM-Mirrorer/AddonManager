-- AddonManager load timing plan. Pure Lua 5.1, no Windower dependency.
-- Offsets are minimum seconds since batch dispatch begins, not
-- completion/readiness signals. Sorting lets ordinary addons dispatch before
-- a delayed entry even if the delayed entry appeared first in a profile.
local M = {}

function M.plan(list, kind, spacing, overrides)
    local plan, ordinary = {}, 0
    spacing = spacing or 0
    overrides = overrides or {}
    for index, addon in ipairs(list) do
        local special = kind == 'load' and overrides[addon] or nil
        local at
        if special ~= nil then
            at = special
        else
            at = ordinary * spacing
            ordinary = ordinary + 1
        end
        plan[#plan + 1] = {addon = addon, at = at, index = index}
    end
    table.sort(plan, function(a, b)
        if a.at == b.at then return a.index < b.index end
        return a.at < b.at
    end)
    return plan
end

return M
