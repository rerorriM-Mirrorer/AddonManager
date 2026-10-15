-- AddonToggle / Profile Manager
-- Author: Max and A
-- Character profiles and discovery are independent of Windower's original plugin_manager.
-- No code copied from the original plugin_manager; see README for historical inspiration.
_addon.name = 'AddonToggle'
_addon.author = 'Max and A'
_addon.version = '0.3.0-dev.1'
_addon.commands = {'pm'}

require('chat')

local root = windower.addon_path
local data_dir = root .. 'data/'
local profiles_dir = data_dir .. 'profiles/'
local addons_dir = windower.windower_path .. 'addons/'
local generation = 0
local pending_import = nil
local running_capture = nil -- Only the current client's most recent live lua-list request.
local hidden = false -- Preserves the historical //at toggle independently of saved profiles.
local startup_enabled = true
local delay_seconds = 1
local current_character = nil
local requested = {} -- This is intent, NOT a confirmed list of loaded addons.

local function msg(s, color)
    windower.add_to_chat(0, ('[PM] '):color(167) .. tostring(s):color(color or 207))
end

local function trim(s)
    return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function valid_name(s)
    return type(s) == 'string' and s:match('^[%a][%w_%-]*$') ~= nil
end

local function normal(s)
    s = trim(s):lower()
    if valid_name(s) then return s end
    return nil
end

local function ensure_dirs()
    if not windower.dir_exists(data_dir) then windower.create_dir(data_dir) end
    if not windower.dir_exists(profiles_dir) then windower.create_dir(profiles_dir) end
end

local function profile_path(profile)
    return profiles_dir .. profile .. '.txt'
end

local function read_text(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local s = f:read('*a')
    f:close()
    return s
end

local function parse_lines(s)
    local list, seen = {}, {}
    for line in (s or ''):gmatch('[^\r\n]+') do
        local value = normal(line:match('^%s*([^#]+)') or '')
        if value and not seen[value] then
            list[#list + 1] = value
            seen[value] = true
        end
    end
    return list
end

local function read_profile(profile)
    return parse_lines(read_text(profile_path(profile)))
end

local function write_profile(profile, list)
    ensure_dirs()
    -- Simple single-writer persistence for the first test batch. Concurrent edits of
    -- the same profile from separate clients are not transactionally protected.
    local f, err = io.open(profile_path(profile), 'w')
    if not f then
        msg('Cannot save ' .. profile .. ': ' .. tostring(err), 123)
        return false
    end
    for _, addon in ipairs(list) do f:write(addon, '\n') end
    f:close()
    return true
end

local function player_name()
    local p = windower.ffxi.get_player()
    return p and normal(p.name) or nil
end

local function current_profile()
    return current_character or player_name()
end

local function target_profile(arg)
    if not arg or arg == '' then return current_profile() end
    return normal(arg)
end

local function has_value(list, value)
    for _, entry in ipairs(list) do
        if entry == value then return true end
    end
    return false
end

local function combine(a, b)
    local combined, seen = {}, {}
    for _, list in ipairs({a, b}) do
        for _, addon in ipairs(list) do
            if not seen[addon] then
                combined[#combined + 1] = addon
                seen[addon] = true
            end
        end
    end
    return combined
end

local function installed_lookup()
    local installed = {}
    local ok, entries = pcall(windower.get_dir, addons_dir)
    if not ok or type(entries) ~= 'table' then return installed, false end
    for _, folder in ipairs(entries) do
        if valid_name(folder) and windower.dir_exists(addons_dir .. folder) and
            windower.file_exists(addons_dir .. folder .. '/' .. folder .. '.lua') then
            installed[folder:lower()] = folder
        end
    end
    return installed, true
end

local function is_installed(addon)
    local installed, ok = installed_lookup()
    return ok and installed[addon] ~= nil, ok
end

-- //lua list prints *display* names, e.g. "Battle Stations".
-- Resolve only to real scanned folder names to avoid running raw chat strings.
local function canonical_key(value)
    return (tostring(value or ''):lower():gsub('[^%w]', ''))
end

local function installed_display_index(installed)
    local index, collisions = {}, {}
    for key in pairs(installed) do
        local compact = canonical_key(key)
        if not collisions[compact] then
            if index[compact] and index[compact] ~= key then
                index[compact] = nil
                collisions[compact] = true
            else
                index[compact] = key
            end
        end
    end
    return index
end

local function display_list(profile)
    if not profile then msg('No character detected. Specify a profile.', 123); return end
    local list = read_profile(profile)
    msg(profile .. ': ' .. #list .. ' saved addon(s)')
    if #list == 0 then msg('  (empty)', 0) end
    for i, addon in ipairs(list) do
        msg(('  %02d. %s'):format(i, addon), 0)
    end
end

local function edit_profile(verb, profile, addon)
    if not profile or not valid_name(profile) or not addon then
        msg('Usage: //pm ' .. verb .. ' [global|character] <addon>', 123)
        return
    end
    if verb == 'add' and (addon == 'addontoggle' or addon == 'plugin_manager') then
        msg('The managers themselves cannot be added to profiles.', 123)
        return
    end
    local installed, scanned = is_installed(addon)
    if verb == 'add' and scanned and not installed then
        msg(addon .. ' not found in the addon directory. Nothing saved.', 123)
        return
    end
    local list = read_profile(profile)
    local exists = has_value(list, addon)
    if verb == 'add' then
        if exists then msg(addon .. ' already in ' .. profile); return end
        list[#list + 1] = addon
    else
        if not exists then msg(addon .. ' is not in ' .. profile); return end
        local new = {}
        for _, entry in ipairs(list) do
            if entry ~= addon then new[#new + 1] = entry end
        end
        list = new
    end
    if write_profile(profile, list) then
        msg((verb == 'add' and 'Added ' or 'Removed ') .. addon ..
            (verb == 'add' and ' to ' or ' from ') .. profile ..
            ' (saved; running addons unchanged)')
    end
end

local function command_items(kind, list, label, start_after)
    generation = generation + 1
    local token = generation
    if #list == 0 then msg(label .. ': no addons to ' .. kind); return end
    msg(('%s: queued %d %s request(s), %.1fs spacing'):format(
        label, #list, kind, delay_seconds))
    -- Scan only once per batch to avoid expensive repeated directory reads.
    local installed, scanned = installed_lookup()
    coroutine.schedule(function()
        if start_after and start_after > 0 then coroutine.sleep(start_after) end
        for i, addon in ipairs(list) do
            if generation ~= token then
                msg(label .. ': previous queue canceled')
                return
            end
            if kind == 'load' then
                if scanned and not installed[addon] then
                    msg('Skipping missing addon: ' .. addon, 123)
                else
                    windower.send_command('lua load ' .. addon)
                    requested[addon] = 'load requested'
                end
            else
                if addon ~= 'addontoggle' and addon ~= 'plugin_manager' then
                    windower.send_command('lua unload ' .. addon)
                    requested[addon] = 'unload requested'
                else
                    msg('Protected addon not unloaded: ' .. addon, 123)
                end
            end
            if i < #list then coroutine.sleep(delay_seconds) end
        end
        msg(label .. ': requests dispatched (completion not verified)')
    end, 0)
end

local function apply_current(start_after)
    local who = current_profile()
    if not who then msg('No character logged in; //pm apply requires a character.', 123); return end
    local list = combine(read_profile('global'), read_profile(who))
    command_items('load', list, 'global + ' .. who, start_after)
end

local function print_help()
    msg('AddonToggle / Profile Manager v' .. _addon.version, 167)
    local lines = {
        {'//pm list [global|character]', 'Show saved profile'},
        {'//pm add [global|character] <addon>', 'Save an entry; do not load'},
        {'//pm remove [global|character] <addon>', 'Remove entry; do not unload'},
        {'//pm load [global|character]', 'Load a saved list in this client'},
        {'//pm unload [global|character|all]', 'Unload listed addons only'},
        {'//pm apply', 'Load global + current character'},
        {'//pm scan [all]', 'Discover installed Lua addons'},
        {'//pm import loaded [profile]', 'Preview current running addons'},
        {'//pm import init [profile]', 'Preview imports from scripts/init.txt'},
        {'//pm import legacy [profile]', 'Preview original plugin_manager XML'},
        {'//pm import file [profile]', 'Preview data/import.txt'},
        {'//pm import confirm|cancel', 'Commit or discard the preview'},
        {'//pm delay [seconds]', 'Show or set stagger interval (0..10)'},
        {'//pm startup on|off', 'Automatic profile load after login'},
        {'//pm status', 'Current character, profiles, queue info'},
        {'//pm restart', 'Reload the profile manager'},
        {'//pm unload manager', 'Unload the profile manager itself'},
        {'//at', 'Original BarFiller/EquipViewer toggle'},
    }
    for _, line in ipairs(lines) do
        windower.add_to_chat(0, ('  //pm'):color(200) ..
            line[1]:sub(5):color(207) .. (' -> '):color(200) .. line[2]:color(0))
    end
end

local function scan_installed(show_all)
    local lookup, ok = installed_lookup()
    if not ok then msg('Cannot scan Windower addons directory', 123); return end
    local names = {}
    for _, name in pairs(lookup) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    local managed = combine(read_profile('global'),
        read_profile(current_profile() or 'global'))
    msg(('Found %d installed Lua addon(s); profiles are not changed'):format(#names))
    local limit = show_all and #names or math.min(#names, 18)
    for i = 1, limit do
        local name = names[i]
        msg(('  %s%s'):format(name,
            has_value(managed, name:lower()) and ' [listed]' or ''), 0)
    end
    if limit < #names then msg('Use //pm scan all for the complete catalog') end
end

local function parse_init(s)
    local list = {}
    for line in (s or ''):gmatch('[^\r\n]+') do
        line = trim(line)
        if not line:match('^%-%-') and not line:match('^#') then
            for verb, name in line:lower():gmatch('lua%s+(%a+)%s+([%w_%-]+)') do
                if verb == 'load' or verb == 'l' then
                    local addon = normal(name)
                    if addon then list[#list + 1] = addon end
                end
            end
        end
    end
    return combine(list, {})
end

local function parse_legacy(s, profile)
    -- Original plugin_manager uses <settings><Name><addon>...</addon></Name>.
    local body = (s or ''):match('<settings[^>]*>(.-)</settings>')
    if not body then return nil end
    for section, content in body:gmatch('<([%w_%-]+)[^>]*>(.-)</%1>') do
        if section:lower() == profile then
            local items = {}
            for name in content:gmatch('<addon[^>]*>%s*([%w_%-]+)%s*</addon>') do
                local addon = normal(name)
                if addon then items[#items + 1] = addon end
            end
            return combine(items, {})
        end
    end
    return nil
end

-- Capture //lua list output through the same incoming-text stream used by
-- Windower's Logger addon. This is an experimental live snapshot, not a
-- direct API exposing the runtime addon registry.
local function capture_line(value)
    if not running_capture or running_capture.finished or type(value) ~= 'string' then return end
    value = value:strip_colors()
    for line in value:gmatch('[^\r\n]+') do
        if line:find('Currently loaded addons:', 1, true) then
            running_capture.started = true
            running_capture.lines = {}
        elseif running_capture.started then
            local name = line:match('^  +(.+)$')
            if name then
                name = trim(name)
                if name ~= '' then
                    running_capture.lines[#running_capture.lines + 1] = name
                end
            elseif trim(line) ~= '' and #running_capture.lines > 0 then
                -- Ignore any following unrelated game chat after the list.
                running_capture.finished = true
                break
            end
        end
    end
end

local function finish_loaded_capture(capture)
    if running_capture ~= capture then return end
    running_capture = nil
    if not capture.started or #capture.lines == 0 then
        msg('Could not capture //lua list. No import prepared; //pm import file remains available.', 123)
        return
    end

    local installed, ok = installed_lookup()
    if not ok then
        msg('Cannot scan addon folders to validate captured names. No import prepared.', 123)
        return
    end
    local index = installed_display_index(installed)
    local names, protected, unresolved = {}, 0, {}
    for _, display in ipairs(capture.lines) do
        local addon = index[canonical_key(display)]
        if not addon then
            unresolved[#unresolved + 1] = display
        elseif addon == 'addontoggle' or addon == 'plugin_manager' then
            protected = protected + 1
        elseif not has_value(names, addon) then
            names[#names + 1] = addon
        end
    end
    local existing = read_profile(capture.target)
    local additions = {}
    for _, addon in ipairs(names) do
        if not has_value(existing, addon) then
            additions[#additions + 1] = addon
        end
    end
    pending_import = {source = 'loaded', target = capture.target, names = additions}
    msg(('Live snapshot: %d displayed -> %s: %d new, %d protected, %d unresolved'):format(
        #capture.lines, capture.target, #additions, protected, #unresolved))
    for _, addon in ipairs(additions) do msg('  + ' .. addon, 0) end
    for _, display in ipairs(unresolved) do
        msg('  ? Unmatched display name: ' .. display, 123)
    end
    msg('Snapshot from this client only. No changes yet. //pm import confirm|cancel')
end

local function begin_loaded_capture(target)
    if not target then msg('Specify a character or log in first.', 123); return end
    pending_import = nil
    local capture = {target = target, started = false, finished = false, lines = {}}
    running_capture = capture
    msg('Requesting //lua list and capturing this client...')
    windower.send_command('lua list')
    coroutine.schedule(function()
        coroutine.sleep(2)
        finish_loaded_capture(capture)
    end, 0)
end

windower.register_event('incoming text', function(_, message, _, _, blocked)
    if not blocked then capture_line(message) end
end)

local function preview_import(source, target)
    if not target then msg('Specify a character or log in first.', 123); return end
    local candidates
    if source == 'loaded' then
        begin_loaded_capture(target)
        return
    elseif source == 'init' then
        local script = read_text(windower.windower_path .. 'scripts/init.txt')
        if not script then msg('Cannot find Windower/scripts/init.txt', 123); return end
        candidates = parse_init(script)
    elseif source == 'legacy' then
        local xml = read_text(addons_dir .. 'plugin_manager/data/settings.xml')
        if not xml then msg('Cannot find plugin_manager/data/settings.xml', 123); return end
        candidates = parse_legacy(xml, target)
        if not candidates then msg('No matching <' .. target .. '> section in legacy XML', 123); return end
    elseif source == 'file' then
        local raw = read_text(data_dir .. 'import.txt')
        if not raw then msg('Create AddonToggle/data/import.txt first.', 123); return end
        candidates = parse_lines(raw)
    else
        msg('Use //pm import loaded|init|legacy|file [profile]', 123)
        return
    end
    local current = read_profile(target)
    local additions = {}
    local lookup, can_scan = installed_lookup()
    local missing = 0
    for _, name in ipairs(candidates) do
        if can_scan and not lookup[name] then
            missing = missing + 1
        elseif not has_value(current, name) and not has_value(additions, name)
            and name ~= 'addontoggle' and name ~= 'plugin_manager' then
            additions[#additions + 1] = name
        end
    end
    pending_import = {source = source, target = target, names = additions}
    msg(('Preview %s -> %s: %d new; %d unavailable skipped'):format(
        source, target, #additions, missing))
    for _, name in ipairs(additions) do msg('  + ' .. name, 0) end
    msg('No changes yet. //pm import confirm or //pm import cancel.')
end

local function import_command(source, target)
    if source == 'cancel' then pending_import = nil; msg('Import canceled'); return end
    if source == 'confirm' then
        if not pending_import then msg('Nothing awaiting confirmation.', 123); return end
        local p = pending_import
        local combined = combine(read_profile(p.target), p.names)
        if write_profile(p.target, combined) then
            msg(('Imported %d entry/entries into %s; saved.'):format(#p.names, p.target))
            pending_import = nil
        end
        return
    end
    preview_import(source, target_profile(target))
end

local function read_options()
    local saved = read_text(data_dir .. 'options.txt') or ''
    for key, value in saved:gmatch('([%w_]+)%s*=%s*([^\r\n]+)') do
        if key == 'delay' then
            local n = tonumber(value)
            if n and n >= 0 and n <= 10 then delay_seconds = n end
        elseif key == 'startup' then
            startup_enabled = trim(value) ~= 'off'
        end
    end
end

local function save_options()
    ensure_dirs()
    local f, err = io.open(data_dir .. 'options.txt', 'w')
    if not f then msg('Cannot save options: ' .. tostring(err), 123); return false end
    f:write('startup=', startup_enabled and 'on' or 'off', '\n')
    f:write('delay=', tostring(delay_seconds), '\n')
    f:close()
    return true
end

local function dispatch(...)
    local args = {...}
    local verb = (args[1] or ''):lower()
    if verb == 'legacy-toggle' then
        if not hidden then
            windower.send_command('lua unload barfiller; wait 0.2; lua unload equipviewer')
        else
            windower.send_command('lua load barfiller; wait 0.2; lua load equipviewer')
        end
        hidden = not hidden
        msg('Legacy overlays ' .. (hidden and 'hidden' or 'restored'))
    elseif verb == 'help' or verb == '' then
        print_help()
    elseif verb == 'list' then
        display_list(target_profile(args[2]))
    elseif verb == 'add' or verb == 'remove' then
        local p, addon
        if args[3] then p, addon = normal(args[2]), normal(args[3])
        else p, addon = current_profile(), normal(args[2]) end
        edit_profile(verb, p, addon)
    elseif verb == 'load' or verb == 'unload' then
        if verb == 'load' and (args[2] or ''):lower() == 'all' then
            -- Symmetric with "unload all": global + active character, deduplicated.
            apply_current()
        elseif verb == 'unload' and (args[2] or ''):lower() == 'manager' then
            generation = generation + 1
            windower.send_command('lua unload AddonToggle')
        elseif verb == 'unload' and (args[2] or ''):lower() == 'all' then
            local who = current_profile()
            if not who then msg('Log in to use //pm unload all', 123); return end
            command_items('unload', combine(read_profile('global'), read_profile(who)),
                'global + ' .. who)
        else
            local p = target_profile(args[2])
            if not p then msg('Specify a character or log in first.', 123); return end
            command_items(verb, read_profile(p), p)
        end
    elseif verb == 'apply' then
        apply_current()
    elseif verb == 'scan' then
        scan_installed((args[2] or ''):lower() == 'all')
    elseif verb == 'import' then
        import_command((args[2] or ''):lower(), args[3])
    elseif verb == 'delay' then
        if not args[2] then msg(('Current load spacing: %.1f seconds'):format(delay_seconds)); return end
        local seconds = tonumber(args[2])
        if not seconds or seconds < 0 or seconds > 10 then
            msg('Usage: //pm delay <0..10 seconds>', 123); return
        end
        delay_seconds = seconds
        if save_options() then msg('Load spacing saved: ' .. tostring(delay_seconds) .. 's') end
    elseif verb == 'startup' then
        if args[2] ~= 'on' and args[2] ~= 'off' then
            msg('Startup is ' .. (startup_enabled and 'on' or 'off') ..
                '. Usage: //pm startup on|off'); return
        end
        startup_enabled = args[2] == 'on'
        if save_options() then msg('Automatic profile loading: ' .. args[2]) end
    elseif verb == 'status' then
        local who = current_profile() or '(character not logged in)'
        msg('v' .. _addon.version .. ' | character: ' .. who ..
            ' | startup: ' .. (startup_enabled and 'on' or 'off') ..
            ' | spacing: ' .. tostring(delay_seconds) .. 's')
        msg('Global: ' .. #read_profile('global') .. ' | character: ' ..
            (who ~= '(character not logged in)' and
                #read_profile(who) or 0) ..
            ' | command requests tracked: ' .. tostring((function()
                local count = 0
                for _ in pairs(requested) do count = count + 1 end
                return count
            end)()) .. ' (unverified)')
    elseif verb == 'restart' then
        generation = generation + 1
        windower.send_command('lua reload AddonToggle')
    else
        msg('Unknown command: ' .. verb, 123)
        print_help()
    end
end

windower.register_event('addon command', dispatch)

windower.register_event('load', function()
    ensure_dirs()
    read_options()
    windower.send_command('alias at lua c AddonToggle legacy-toggle')
    current_character = player_name()
    if current_character and startup_enabled then
        apply_current(3)
    end
end)

windower.register_event('login', function(name)
    current_character = normal(name) or player_name()
    generation = generation + 1
    if current_character and startup_enabled then apply_current(3) end
end)

windower.register_event('logout', function()
    generation = generation + 1
    current_character = nil
    pending_import = nil
    running_capture = nil
end)

windower.register_event('unload', function()
    generation = generation + 1
    running_capture = nil
    windower.send_command('unalias at')
end)
