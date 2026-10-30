-- AddonManager load schedule tests (Lua 5.1, no Windower).
local planner = dofile('am_schedule.lua')

local function expect(plan, names, times)
    assert(#plan == #names)
    for i, item in ipairs(plan) do
        assert(item.addon == names[i], ('unexpected addon at %d: %s'):format(i, item.addon))
        assert(item.at == times[i], ('unexpected time for %s: %s'):format(item.addon, item.at))
    end
end

-- Default: every addon at t=0, preserving the saved profile order.
expect(planner.plan({'trust', 'gilfinder', 'equipviewer'}, 'load', 0), 
    {'trust', 'gilfinder', 'equipviewer'}, {0, 0, 0})

-- A delayed first item must not delay otherwise immediate requests.
expect(planner.plan({'trust', 'gilfinder', 'equipviewer'}, 'load', 0,
    {trust = 2, gilfinder = 0.5}),
    {'equipviewer', 'gilfinder', 'trust'}, {0, 0.5, 2})

-- Two equal offsets preserve source order.
expect(planner.plan({'trust', 'gilfinder', 'equipviewer'}, 'load', 0,
    {trust = 2, gilfinder = 2}),
    {'equipviewer', 'trust', 'gilfinder'}, {0, 2, 2})

-- Nonzero global spacing still works; explicit offsets are independent
-- of the ordinary-item slots, so a delayed first item doesn't block others.
expect(planner.plan({'trust', 'gilfinder', 'equipviewer'}, 'load', 1,
    {trust = 3}), {'gilfinder', 'equipviewer', 'trust'}, {0, 1, 3})

-- Unloads do not use per-addon LOAD offsets. Keep the legacy spacing.
expect(planner.plan({'trust', 'gilfinder'}, 'unload', 1,
    {trust = 3}), {'trust', 'gilfinder'}, {0, 1})

assert(#planner.plan({}, 'load', 0, {}) == 0)
print('AddonManager load schedule: PASS')
