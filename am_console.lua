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
    local token = (character or 'unknown'):lower() .. '_' ..
        tostring(os.time()) .. '_' .. tostring(math.floor(os.clock() * 1000000)) ..
        '_' .. tostring(serial)
    return {path = path .. 'console.log', offset = position, token = token,
        begin_marker = 'AM_LIST_BEGIN_' .. token,
        end_marker = 'AM_LIST_END_' .. token}
end

function M.commands(capture)
    return {
        'console_echo "' .. capture.begin_marker .. '"',
        'lua list console',
        'console_echo "' .. capture.end_marker .. '"',
    }
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

    local stage, names = 'begin', {}
    for raw in data:gmatch('[^\r\n]+') do
        local line = trim(raw)
        local is_begin = line:find(capture.begin_marker, 1, true) ~= nil
        local is_end = line:find(capture.end_marker, 1, true) ~= nil
        if is_begin then
            if stage ~= 'begin' then return nil, 'duplicate or interleaved list marker' end
            stage = 'heading'
        elseif is_end then
            if stage ~= 'names' or #names == 0 then
                return nil, 'console list ended before valid addon entries'
            end
            return names
        elseif stage ~= 'begin' then
            if line:find('AM_LIST_BEGIN_', 1, true)
                or line:find('AM_LIST_END_', 1, true) then
                return nil, 'another client interleaved a console audit'
            elseif line:find('Currently loaded addons:', 1, true) then
                if stage ~= 'heading' then return nil, 'duplicate list heading' end
                stage = 'names'
            elseif stage == 'names' then
                -- Console output usually preserves the two-space list indent.
                -- Accept whitespace-prefixed names only; non-list console text
                -- between the delimiters is suspect and fails closed.
                local entry = raw:match('^%s%s+(.+)%s*$')
                if not entry then
                    return nil, 'unexpected console text inside loaded list'
                end
                entry = trim(entry)
                if entry == '' then return nil, 'empty addon name in list' end
                names[#names + 1] = entry
            end
        end
    end
    if stage == 'begin' then return nil, 'begin marker not observed in console.log' end
    return nil, 'complete marker-delimited console list not observed'
end

return M
