-- Deterministic same-computer multi-client IPC simulation for am_cluster.lua.
-- This does not launch Windower or FFXI; it tests the actual module logic.
local clock, queue, clients, records, messages = 0, {}, {}, {}, {}
local function later(fn, delay)
    queue[#queue + 1] = {t = clock + (delay or 0), callback = fn}
end
local function advance(delta)
    local target, spins = clock + delta, 0
    while true do
        local index, soonest
        for i, item in ipairs(queue) do
            if item.t <= target and (not soonest or item.t < soonest) then
                index, soonest = i, item.t
            end
        end
        if not index then break end
        spins = spins + 1
        assert(spins < 10000, 'scheduler loop')
        clock = soonest
        local item = table.remove(queue, index)
        item.callback()
    end
    clock = target
end
local function clone(name, missing)
    local client = {name = name:lower(), logs = {}, missing = missing, ipc = nil}
    local env = setmetatable({
        windower = {
            ffxi = {
                get_info = function() return {logged_in = client.logged_in ~= false} end,
                get_player = function() return {name = client.name} end,
            },
            send_ipc_message = function(message)
                messages[#messages + 1] = {from = client.name, msg = message}
                for _, receiver in pairs(clients) do
                    if receiver ~= client and receiver.ipc then
                        later(function() receiver.ipc(message) end, 0)
                    end
                end
            end,
            register_event = function(event, callback)
                assert(event == 'ipc message')
                client.ipc = callback
            end,
        },
        coroutine = {schedule = later},
    }, {__index = _G})
    local loader = assert(loadfile('am_cluster.lua'))
    setfenv(loader, env)
    client.controller = loader()({
        message = function(s) client.logs[#client.logs + 1] = s end,
        check = function(addon)
            if client.missing == addon then return false, 'not installed' end
            if addon ~= 'trust' and addon ~= 'xivcrossbar' then return false, 'unknown' end
            return true
        end,
        run = function(action, addon)
            if client.missing == addon then return false, 'not installed' end
            records[#records + 1] = {who = client.name, action = action,
                addon = addon, time = clock}
            return true
        end,
    })
    clients[#clients + 1] = client
    return client
end

local cioara = clone('Cioara')
local myrr = clone('Myrr')
local clairvaux = clone('Clairvaux')

cioara.controller.handle('load', 'trust')
advance(0.55)
assert(#records == 1 and records[1].who == 'clairvaux',
    'first known peer should dispatch before initiator')
advance(2.05)
assert(#records == 2 and records[2].who == 'myrr', 'second peer missing')
advance(2.05)
assert(#records == 3 and records[3].who == 'cioara', 'initiator not last')
assert(records[2].time - records[1].time >= 2, 'second request not staggered')
assert(records[3].time - records[2].time >= 2, 'initiator not staggered')

-- Every client independently processes one request; no duplicate on finished run.
local msg
for _, entry in ipairs(messages) do
    if entry.msg:find(' run ', 1, true) then msg = entry.msg; break end
end
assert(msg)
clairvaux.ipc(msg)
advance(0)
assert(#records == 3, 'replayed IPC command caused duplicate reload/load')

-- Stagger is an independent option on the initiating client.
local saved = cioara.controller.gap('0.2')
assert(saved == 0.2)
myrr.controller.handle('reload', 'xivcrossbar')
advance(0.55)
assert(#records == 4 and records[4].action == 'reload',
    'reload did not reach another client')
advance(4.2)
assert(#records == 6 and records[6].who == 'myrr',
    'reload did not finish with initiator')
assert(records[5].time - records[4].time >= 2,
    'default leader stagger changed unexpectedly')

-- Inactive/missing client does not participate in discovery.
clairvaux.logged_in = false
cioara.controller.handle('load', 'trust')
advance(0.6)
assert(records[7].who == 'myrr', 'logged-out client participated')
advance(0.25)
assert(records[8].who == 'cioara', 'two-client ordering failed')
clairvaux.logged_in = true

-- One peer without the requested addon must reject discovery; no loads.
clairvaux.missing = 'trust'
local baseline = #records
cioara.controller.handle('load', 'trust')
advance(1)
assert(#records == baseline, 'rejected peer should cancel entire batch')
clairvaux.missing = nil

-- Cancellation before discovery ends never dispatches a command.
cioara.controller.handle('load', 'trust')
cioara.controller.handle('cancel')
advance(1)
assert(#records == baseline, 'cancelled batch dispatched commands')

-- Bare all reload requires an explicit target; prevents mass reloads.
cioara.controller.handle('reload')
advance(1)
assert(#records == baseline, 'bare reload should require an addon')

print('AddonManager multi-client IPC smoke: PASS (' ..
    #records .. ' simulated addon commands)')
