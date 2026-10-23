-- A: opt-in-to-file (never changes console_log) capture of LuaCore's
-- "lua list console". Only a fresh, marker-bounded result is authoritative.
-- Windower/console.log may be shared by multiple clients: reject interleaving.
local M = {}
local serial = 0

local function trim(value)
    return (value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

function M.begin(path, character)
    if type(path) ~= 'string' or path == '' then
        return nil, 'Windower path unavailable'
    end
    local f = io.open(path .. 'console.log', 'rb')
    if not f then
        return nil, 'console.log unavailable; enable console_log 1 or use //am capture chat'
    end
    local position = f:seek('end')
    f:close()
    if not position then return nil, 'Cannot seek console.log' end
    serial = serial + 1
    -- The file offset isolates a fresh request; the character identifies
    -- the client, and a short counter distinguishes repeated local audits.
    -- Keep internal log boundaries readable rather than dumping timestamps.
    local who = character or 'Unknown'
    local check = tostring(serial)
    return {path = path .. 'console.log', offset = position,
        begin_marker = 'AddonManager | ' .. who .. ' | Checking loaded addons (#' .. check .. ')',
        end_marker = 'AddonManager | ' .. who .. ' | Finished listing addons (#' .. check .. ')'}
end

function M.commands(capture)
    return {
        'console_echo "' .. capture.begin_marker .. '"',
        'lua list console',
        'console_echo "' .. capture.end_marker .. '"',
    }
end

-- Observe command completion through the native log instead of assuming
-- three successive send_command calls will execute in FIFO order. This is
-- *only* a staging signal; finish() still performs authoritative validation.
function M.progress(capture)
    local f = io.open(capture.path, 'rb')
    if not f then return nil, 'console.log unavailable while sequencing' end
    local size = f:seek('end')
    if not size or size < capture.offset or size - capture.offset > 131072 then
        f:close()
        return nil, 'console.log changed outside safe capture bounds'
    end
    f:seek('set', capture.offset)
    local data = f:read(size - capture.offset) or ''
    f:close()

    local begun, heading = false, false
    for raw in data:gmatch('[^\r\n]+') do
        local body = raw:match("^%s*%d%d:%d%d:%d%d%s*>(.*)$") or raw
        local line = trim(body)
        if line:find(capture.begin_marker, 1, true) then
            begun, heading = true, false
        elseif begun then
            if line:find('Currently loaded addons:', 1, true) then
                heading = true
            elseif heading and body:match('^%s%s+%S') then
                return 'names_seen'
            end
        end
    end
    return begun and 'begin_seen' or 'waiting_begin'
end

function M.finish(capture)
    local f = io.open(capture.path, 'rb')
    if not f then return nil, 'console.log unavailable during capture' end
    local size = f:seek('end')
    if not size or size < capture.offset then
        f:close()
        return nil, 'console.log truncated'
    end
    local bytes = size - capture.offset
    if bytes > 131072 then
        f:close()
        return nil, 'console.log grew beyond 128 KiB capture limit'
    end
    f:seek('set', capture.offset)
    local data = f:read(bytes) or ''
    f:close()
    if data == '' then return nil, 'no new console.log text' end

    local stage, names, ignored_errors = 'begin', {}, 0
    for raw in data:gmatch('[^\r\n]+') do
        -- ConsoleBGPlus log lines may begin '20:58:48 >   autoex'.
        -- Remove the timestamp/command prompt but preserve name indentation.
        local body = raw:match("^%s*%d%d:%d%d:%d%d%s*>(.*)$") or raw
        local line = trim(body)
        local is_begin = line:find(capture.begin_marker, 1, true) ~= nil
        local is_end = line:find(capture.end_marker, 1, true) ~= nil
        if is_begin then
            if stage ~= 'begin' then return nil, 'duplicate or interleaved list marker' end
            stage = 'heading'
        elseif is_end then
            if stage ~= 'names' or #names == 0 then
                return nil, 'console list ended before valid addon entries'
            end
            return names, ignored_errors
        elseif stage ~= 'begin' then
            if line:find('AddonManager | ', 1, true)
                or line:find('AM_LIST_BEGIN_', 1, true)
                or line:find('AM_LIST_END_', 1, true) then
                return nil, 'another client interleaved a console audit'
            elseif line:find('Currently loaded addons:', 1, true) then
                if stage ~= 'heading' then return nil, 'duplicate list heading' end
                stage = 'names'
            elseif stage == 'names' then
                -- Ignore only recognizable Lua runtime stack/error lines.
                -- Preserve strict list format and reject foreign audit markers.
                if line:match('%.lua:%d+') or line:match('^stack traceback:')
                    or line:find('attempt to index', 1, true) then
                    ignored_errors = ignored_errors + 1
                else
                    local entry = body:match('^%s%s+(.+)')
                    if not entry then
                        return nil, 'unexpected console text: ' .. line:sub(1, 100)
                    end
                    entry = trim(entry)
                    if entry == '' then return nil, 'empty addon name in list' end
                    names[#names + 1] = entry
                end
            end
        end
    end
    if stage == 'begin' then return nil, 'begin marker not observed in console.log' end
    return nil, 'complete marker-delimited console list not observed'
end

return M
