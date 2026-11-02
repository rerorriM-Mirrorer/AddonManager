-- IPC coordinator for //am all <load|reload> <addon>.
-- Same-computer Windower IPC, patterned after SlowEnter's acknowledged roster.
-- Completion is a fresh per-client loaded-addon observation, not just dispatch.
return function(api)
    local prefix, active, serial, gap = 'AMALL2', nil, 0, 2
    local seen = {}
    local dispatch

    local function name()
        local info = windower.ffxi.get_info and windower.ffxi.get_info()
        local player = windower.ffxi.get_player()
        if info and not info.logged_in then return nil end
        return player and player.name and player.name:lower() or nil
    end

    local function send(to, verb, token, value)
        local me = name()
        if me and windower.send_ipc_message then
            windower.send_ipc_message(table.concat(
                {prefix, me, to, verb, token, value or '-'}, ' '))
        end
    end

    local function later(session, seconds, fn)
        coroutine.schedule(function()
            if active == session then fn() end
        end, seconds)
    end

    local function mark_seen(token)
        local key = {}
        seen[token] = key
        coroutine.schedule(function()
            if seen[token] == key then seen[token] = nil end
        end, 120)
    end

    local function cancel(reason)
        local s = active
        if not s then return end
        active = nil
        if s.leader == s.me then send('*', 'cancel', s.token)
        else send(s.leader, 'abort', s.token) end
        api.message('All-client batch stopped: ' .. reason, 123)
    end

    -- A fresh, marker-bounded lua-list check on the actual client is the
    -- acknowledgment. This proves presence afterward, not that an addon's
    -- own initialization code completed; reloads cannot prove restart from
    -- presence alone.
    local function verify(s, callback)
        local responded = false
        local ok, err = pcall(api.verify, s.verb, s.addon, function(outcome, detail)
            if responded then return end
            responded = true
            if active == s then callback(outcome, detail) end
        end)
        if not ok and not responded and active == s then
            callback('inconclusive', 'verification error: ' .. tostring(err))
        end
    end

    local function complete(s, who, outcome, detail)
        if active ~= s or s.phase ~= 'waiting' or s.current ~= who then return end
        if outcome ~= 'present' and outcome ~= 'absent' then outcome = 'inconclusive' end
        s.results[who] = outcome
        s.phase = 'gap'
        if outcome == 'present' then
            api.message(who .. ': ' .. s.addon .. ' loaded after ' ..
                s.verb .. ' (confirmed by fresh lua list).')
        elseif outcome == 'absent' then
            api.message(who .. ': ' .. s.addon .. ' absent after ' ..
                s.verb .. ' (fresh lua list).', 123)
        else
            api.message(who .. ': ' .. s.addon ..
                ' not verified after ' .. s.verb ..
                (detail and ' (' .. detail .. ')' or '') .. '.', 123)
        end
        if s.index == #s.order then
            local present, absent, inconclusive = 0, 0, 0
            for _, member in ipairs(s.order) do
                local result = s.results[member]
                if result == 'present' then present = present + 1
                elseif result == 'absent' then absent = absent + 1
                else inconclusive = inconclusive + 1 end
            end
            send('*', 'finish', s.token)
            active = nil
            api.message(('Batch complete: %d loaded afterward; %d absent; %d inconclusive (%d client(s)).'):format(
                present, absent, inconclusive, #s.order),
                absent + inconclusive > 0 and 123 or 207)
        else
            later(s, s.gap, function() dispatch(s) end)
        end
    end

    dispatch = function(s)
        if active ~= s then return end
        s.index = s.index + 1
        local who = s.order[s.index]
        s.current, s.phase = who, 'waiting'
        if who == s.me then
            local ok, reason = api.run(s.verb, s.addon)
            if ok then
                verify(s, function(outcome, detail) complete(s, who, outcome, detail) end)
            else cancel(reason or 'local dispatch failed') end
        else
            send(who, 'run', s.token, s.addon)
        end
        local index = s.index
        later(s, 20, function()
            if s.phase == 'waiting' and s.index == index then
                cancel(who .. ': no verification response; no retry issued')
            end
        end)
    end

    local function start(verb, addon)
        local me = name()
        if not me then api.message('Log in before using //am all.', 123); return end
        if not windower.send_ipc_message then
            api.message('Windower IPC is unavailable in this client.', 123)
            return
        end
        if active then api.message('An all-client batch is active. Use //am all cancel.', 123); return end
        local ok, reason = api.check(addon)
        if not ok then api.message(reason, 123); return end
        serial = serial + 1
        local token = me .. '-' .. os.time() .. '-' .. serial .. '-' ..
            math.floor(os.clock() * 100000)
        local s = {me = me, leader = me, verb = verb, addon = addon,
            token = token, members = {}, results = {}, index = 0,
            phase = 'discovering', gap = gap}
        active = s
        mark_seen(token)
        send('*', 'probe', token, verb .. ':' .. addon)
        api.message('Discovering AddonManager clients; ' .. me .. ' will run last.')
        later(s, 0.5, function()
            s.order = {}
            for who in pairs(s.members) do s.order[#s.order + 1] = who end
            table.sort(s.order)
            s.order[#s.order + 1] = me
            api.message('Order: ' .. table.concat(s.order, ' -> ') ..
                ' (' .. s.gap .. 's between dispatches).')
            dispatch(s)
        end)
        later(s, 240, function() cancel('batch expired') end)
    end

    local function receive(message)
        if type(message) ~= 'string' or #message > 256 then return end
        local tag, from, to, verb, token, value =
            message:match('^(%S+) (%S+) (%S+) (%S+) (%S+) (%S+)$')
        if tag ~= prefix or not from or not to or not verb or not token then return end
        local me = name()
        if not me or from == me or (to ~= '*' and to ~= me)
            or not from:match('^[%a]+$')
            or not token:match('^[%w%-]+$') then return end

        local s = active
        if verb == 'probe' then
            local action, addon = value:match("^(%a+):([%a][%w_%-]*)$")
            if seen[token] then
                if s and s.token == token and s.leader == from then send(from, 'ready', token) end
                return
            end
            mark_seen(token)
            if s then send(from, 'busy', token); return end
            local ok, reason = api.check(addon)
            if not ok then
                send(from, 'fail', token)
                api.message('Rejected all-client ' .. action .. ' ' .. addon ..
                    ': ' .. tostring(reason), 123)
                return
            end
            s = {me = me, leader = from, verb = action, addon = addon,
                token = token, phase = 'ready'}
            active = s
            send(from, 'ready', token)
            later(s, 240, function() cancel('leader timed out') end)
            return
        end
        if not s or s.token ~= token then return end
        if s.leader == me then
            if verb == 'ready' then
                if s.phase == 'discovering' then s.members[from] = true
                elseif not s.members[from] then send(from, 'cancel', token) end
            elseif verb == 'busy' or verb == 'fail' then
                cancel(from .. ': not available (' .. verb .. ')')
            elseif verb == 'abort' and s.members[from] then
                cancel(from .. ': cancelled locally')
            elseif verb == 'checked' and s.members[from] then
                complete(s, from, value)
            end
        elseif from == s.leader then
            if verb == 'cancel' or verb == 'finish' then
                active = nil
                if verb == 'cancel' then api.message('All-client batch cancelled by ' .. from) end
            elseif verb == 'run' and s.phase == 'ready' and value == s.addon then
                -- Mark before dispatch: duplicate IPC can never issue the same command twice.
                s.phase = 'running'
                local ok, reason = api.run(s.verb, s.addon)
                if ok then
                    s.phase = 'checking'
                    verify(s, function(outcome, detail)
                        if active ~= s then return end
                        s.phase = 'done'
                        if outcome ~= 'present' and outcome ~= 'absent' then
                            outcome = 'inconclusive'
                        end
                        send(s.leader, 'checked', token, outcome)
                        if outcome ~= 'present' then
                            api.message('Local ' .. s.addon .. ' ' .. s.verb ..
                                ' verification: ' .. (detail or outcome), 123)
                        end
                    end)
                else
                    active = nil
                    send(s.leader, 'abort', token)
                    api.message(tostring(reason or 'dispatch failed'), 123)
                end
            end
        end
    end
    windower.register_event('ipc message', receive)

    return {
        cancel = cancel,
        status = function()
            api.message('All clients: ' .. (active and
                (active.phase .. ' for ' .. active.verb .. ' ' .. active.addon) or 'idle') ..
                ' | stagger ' .. gap .. 's.')
        end,
        gap = function(value)
            if not value then api.message('Cross-client stagger: ' .. gap .. 's.'); return gap end
            local n = tonumber(value)
            if not n or n ~= n or n < 0.1 or n > 10 then
                api.message('Use //am stagger <0.1..10> seconds.', 123)
                return
            end
            gap = n
            api.message('Cross-client stagger set to ' .. gap .. 's (per initiating client).')
            return n
        end,
        handle = function(verb, addon, extra)
            verb = (verb or ''):lower()
            if verb == 'cancel' and not addon and not extra then
                cancel('user command')
                return
            end
            if (verb ~= 'load' and verb ~= 'reload') or not addon or extra then
                api.message('Use //am all load <addon> | //am all reload <addon> | //am all cancel.', 123)
                return
            end
            if not addon:match('^[%a][%w_%-]*$') then
                api.message('Invalid addon name.', 123); return
            end
            start(verb, addon:lower())
        end,
    }
end
