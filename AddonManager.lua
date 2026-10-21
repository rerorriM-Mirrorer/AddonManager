-- AddonManager / Profile Manager
-- Author: Max and A
-- Character profiles and discovery are independent of Windower's original plugin_manager.
-- No code copied from the original plugin_manager; see README for historical inspiration.
_addon.name = 'AddonManager'
_addon.author = 'Max and A'
_addon.version = '0.5.0-dev.4'
_addon.commands = {'am'}

require('chat')
local console_capture = require('am_console')

local root = windower.addon_path
local data_dir = root .. 'data/'
local profiles_dir = data_dir .. 'profiles/'
local addons_dir = windower.windower_path .. 'addons/'
local generation = 0
local pending_import = nil
local pending_prune = nil -- Previewed duplicate cleanup; never writes without confirmation.
local running_capture = nil -- Only the current client's most recent live lua-list request.
local startup_enabled = true
local verify_enabled = true -- Report startup discrepancies; never auto-repair.
local capture_mode = 'console' -- Quiet native console; chat remains a fallback option.
local delay_seconds = 1
local current_character = nil
local requested = {} -- This is intent, NOT a confirmed list of loaded addons.
local begin_audit -- Assigned below; startup queue callback uses it after source initialization.
local cluster

local function msg(s, color)
    windower.add_to_chat(0, ('[AM] '):color(167) .. tostring(s):color(color or 207))
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
        msg('Usage: //am ' .. verb .. ' [global|character] <addon>', 123)
        return
    end
    if verb == 'add' and (addon == 'addonmanager' or addon == 'addontoggle' or addon == 'plugin_manager') then
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

local function command_items(kind, list, label, start_after, after)
    generation = generation + 1
    local token = generation
    if #list == 0 then
        msg(label .. ': no addons to ' .. kind)
        if after then after() end
        return
    end
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
                if addon ~= 'addonmanager' and addon ~= 'addontoggle' and addon ~= 'plugin_manager' then
                    windower.send_command('lua unload ' .. addon)
                    requested[addon] = 'unload requested'
                else
                    msg('Protected addon not unloaded: ' .. addon, 123)
                end
            end
            if i < #list then coroutine.sleep(delay_seconds) end
        end
        msg(label .. ': requests dispatched (completion not verified)')
        if after then after() end
    end, 0)
end

local function apply_current(start_after, check_on_startup)
    local who = current_profile()
    if not who then msg('No character logged in; //am apply requires a character.', 123); return end
    local list = combine(read_profile('global'), read_profile(who))
    local after
    if check_on_startup and verify_enabled then
        -- Allow time for the final dispatched addon to finish initializing.
        -- This is a delay, NOT proof of addon readiness.
        after = function()
            coroutine.schedule(function()
                coroutine.sleep(3)
                if who == current_profile() and verify_enabled then begin_audit('startup') end
            end, 0)
        end
    end
    command_items('load', list, 'global + ' .. who, start_after, after)
end

local function print_help()
    msg('AddonManager / Profile Manager v' .. _addon.version, 167)
    local lines = {
        {'//am list [global|character]', 'Show saved profile'},
        {'//am add [global|character] <addon>', 'Save an entry; do not load'},
        {'//am remove [global|character] <addon>', 'Remove entry; do not unload'},
        {'//am load [global|character]', 'Load a saved list in this client'},
        {'//am unload [global|character|all]', 'Unload listed addons only'},
        {'//am apply', 'Load global + current character'},
        {'//am all load <addon>', 'Stagger load across same-PC clients'},
        {'//am all reload <addon>', 'Stagger reload across same-PC clients'},
        {'//am all cancel', 'Cancel a pending client batch'},
        {'//am stagger [seconds]', 'Cross-client spacing (default 2s)'},
        {'//am scan [all]', 'Discover installed Lua addons'},
        {'//am import loaded [profile]', 'Capture extras beyond global (or full global)'},
        {'//am import init [profile]', 'Preview imports from scripts/init.txt'},
        {'//am import legacy [profile]', 'Preview original plugin_manager XML'},
        {'//am import file [profile]', 'Preview data/import.txt'},
        {'//am import confirm|cancel', 'Commit or discard the preview'},
        {'//am prune [character]', 'Preview profile entries already in global'},
        {'//am prune confirm|cancel', 'Save cleanup or discard preview'},
        {'//am delay [seconds]', 'Show or set stagger interval (0..10)'},
        {'//am startup on|off', 'Automatic profile load after login'},
        {'//am audit', 'Read-only check against lua list'},
        {'//am capture [console|chat]', 'Select audit output (default console)'},
        {'//am verify on|off', 'Startup audit and discrepancy alerts'},
        {'//am status', 'Current character, profiles, queue info'},
        {'//am restart', 'Reload the profile manager'},
        {'//am unload manager', 'Unload the profile manager itself'},
    }
    for _, line in ipairs(lines) do
        windower.add_to_chat(0, ('  //am'):color(200) ..
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
    if limit < #names then msg('Use //am scan all for the complete catalog') end
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

-- Both the live incoming-text event and Logger's saved output use this parser.
local function capture_line(value, snapshot)
    snapshot = snapshot or running_capture
    if not snapshot or snapshot.finished or type(value) ~= 'string' then return end
    value = value:strip_colors()
    for line in value:gmatch('[^\r\n]+') do
        -- Logger optionally adds HH:MM:SS timestamps.
        line = line:gsub('^%d%d:%d%d:%d%d%s+', '')
        if line:find('Currently loaded addons:', 1, true) then
            snapshot.started = true
            snapshot.lines = {}
        elseif snapshot.started then
            local name = line:match('^  +(.+)$')
            if name then
                name = trim(name)
                if name ~= '' then
                    snapshot.lines[#snapshot.lines + 1] = name
                end
            elseif trim(line) ~= '' and #snapshot.lines > 0 then
                snapshot.finished = true
                break
            end
        end
    end
end

-- Optional Logger-file fallback: remember EOF BEFORE requesting lua list.
-- Only appended bytes from this request can become a new snapshot.
local function logger_watermark()
    local player = windower.ffxi.get_player()
    local name = player and player.name
    if not valid_name(name) or not windower.windower_path then return nil end
    local path = windower.windower_path .. 'logs/' ..
        name .. '_' .. os.date('%Y.%m.%d') .. '.log'
    local f = io.open(path, 'rb')
    local offset = 0
    if f then offset = f:seek('end') or 0; f:close() end
    return {path = path, offset = offset}
end

local function logger_fallback(capture)
    local source = capture.logger
    if not source then return false, 'path unavailable' end
    local f = io.open(source.path, 'rb')
    if not f then return false, 'Logger file unavailable' end
    local size = f:seek('end')
    if not size or size < source.offset then
        f:close()
        return false, 'Logger file truncated'
    end
    local new_bytes = size - source.offset
    if new_bytes > 131072 then
        f:close()
        return false, 'Logger output exceeded safe capture limit'
    end
    f:seek('set', source.offset)
    local data = f:read(new_bytes) or ''
    f:close()
    if data == '' then return false, 'no new Logger text' end
    local snapshot = {started = false, finished = false, lines = {}}
    capture_line(data, snapshot)
    if not snapshot.started then return false, 'no list heading in new Logger text' end
    if #snapshot.lines == 0 then return false, 'heading but no names in new Logger text' end
    capture.started = true
    capture.lines = snapshot.lines
    capture.snapshot_source = 'Logger fresh append'
    return true
end

local function finish_audit(capture)
    local installed, ok = installed_lookup()
    if not ok then msg('Audit unavailable: addon folder inventory failed.', 123); return false end
    if capture.character ~= current_profile() then return false end
    local index = installed_display_index(installed)
    local observed, unresolved = {}, {}
    for _, display in ipairs(capture.lines) do
        local addon = index[canonical_key(display)]
        if addon then observed[addon] = true
        else unresolved[#unresolved + 1] = display end
    end
    local expected = combine(read_profile('global'), read_profile(capture.character))
    local missing, unlisted, matched = {}, {}, 0
    local planned = {}
    for _, addon in ipairs(expected) do
        planned[addon] = true
        if observed[addon] then matched = matched + 1
        else missing[#missing + 1] = addon end
    end
    for addon in pairs(observed) do
        if not planned[addon] and addon ~= 'addonmanager' and
            addon ~= 'addontoggle' and addon ~= 'plugin_manager' then
            unlisted[#unlisted + 1] = addon
        end
    end
    table.sort(unlisted)
    -- Automatic reconciliation requires strong evidence of a complete, mappable
    -- current-client list. Logger's observed list includes this addon itself.
    -- No guesses if the heading/rows were cut off or an entry cannot be mapped.
    local actionable = observed.addonmanager == true and #unresolved == 0
    if capture.source == 'reload' and not actionable then
        msg('Safe reload: incomplete lua-list snapshot (manager missing or names unresolved).', 123)
        return false
    end
    local head = ('Audit %s: %d/%d expected loaded; %d missing; %d unmanaged; %d unresolved'):format(
        capture.character, matched, #expected, #missing, #unlisted, #unresolved)
    -- Windower-native addons managed outside profiles count as unmanaged, not errors.
    msg(head, #missing > 0 and 123 or 207)
    for _, addon in ipairs(missing) do msg('  Missing: ' .. addon, 123) end
    if #unresolved > 0 then
        msg('  ' .. #unresolved .. ' display name(s) could not be matched; results may be incomplete.', 123)
    end
    if capture.source == 'manual' then
        for _, addon in ipairs(unlisted) do msg('  Unmanaged: ' .. addon, 0) end
    end
    -- A snapshot can reveal missing addons but never proves a load command succeeded.
    return actionable, missing
end

local function finish_loaded_capture(capture)
    if running_capture ~= capture then return end
    local logger_reason, console_reason
    if capture.mode == 'console' then
        local entries
        entries, console_reason = console_capture.finish(capture.console)
        if entries then
            capture.started, capture.lines = true, entries
            capture.snapshot_source = 'console.log marker bounded'
        end
    elseif not capture.started or #capture.lines == 0 then
        local recovered
        recovered, logger_reason = logger_fallback(capture)
        if recovered then
            msg(('Recovered %d addon names from new Logger text.'):format(#capture.lines))
        end
    end
    running_capture = nil
    if not capture.started or #capture.lines == 0 then
        local live_reason = capture.started and 'heading detected, no entries' or
            'list heading not received'
        local detail
        if capture.mode == 'console' then
            detail = 'console.log: ' .. (console_reason or 'unavailable')
        else
            detail = 'incoming text: ' .. live_reason ..
                '; Logger: ' .. (logger_reason or 'not available')
        end
        if capture.kind == 'audit' then
            msg('Audit inconclusive (' .. detail .. '). No changes made.', 123)
            if capture.done then capture.done(false) end
        else
            msg('Loaded import inconclusive (' .. detail .. '). No import prepared.', 123)
        end
        return
    end
    if capture.kind == 'audit' then
        local ok, missing = finish_audit(capture)
        if capture.done then capture.done(ok, missing) end
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
        elseif addon == 'addonmanager' or addon == 'addontoggle' or addon == 'plugin_manager' then
            protected = protected + 1
        elseif not has_value(names, addon) then
            names[#names + 1] = addon
        end
    end
    local existing = read_profile(capture.target)
    local shared = capture.target ~= 'global' and read_profile('global') or {}
    local additions, in_global, already_saved = {}, 0, 0
    for _, addon in ipairs(names) do
        if has_value(shared, addon) then
            in_global = in_global + 1
        elseif has_value(existing, addon) then
            already_saved = already_saved + 1
        else
            additions[#additions + 1] = addon
        end
    end
    pending_import = {source = 'loaded', target = capture.target, names = additions}
    msg(('Live snapshot: %d displayed -> %s: %d new, %d shared, %d saved, %d protected, %d unresolved'):format(
        #capture.lines, capture.target, #additions, in_global, already_saved, protected, #unresolved))
    for _, addon in ipairs(additions) do msg('  + ' .. addon, 0) end
    for _, display in ipairs(unresolved) do
        msg('  ? Unmatched display name: ' .. display, 123)
    end
    msg('Snapshot from this client only. No changes yet. //am import confirm|cancel')
end

-- Audit/import queries share a single capture pipeline. Console mode never
-- touches console_log; if another addon (e.g. ConsoleBGPlus) has not enabled
-- it, fail closed. Chat mode retains the proven Logger-file fallback.
local function issue_loaded_list(capture)
    capture.mode = capture_mode
    if capture.mode == 'console' then
        local snapshot, err = console_capture.begin(windower.windower_path, current_profile())
        if not snapshot then
            msg('Quiet audit unavailable: ' .. tostring(err) ..
                '. No load requests issued.', 123)
            if capture.done then capture.done(false) end
            return false
        end
        capture.console = snapshot
    else
        capture.logger = logger_watermark()
    end
    running_capture = capture
    if capture.mode == 'console' then
        for _, cmd in ipairs(console_capture.commands(capture.console)) do
            windower.send_command(cmd)
        end
    else
        windower.send_command('lua list')
    end
    coroutine.schedule(function()
        coroutine.sleep(2)
        finish_loaded_capture(capture)
    end, 0)
    return true
end

local function begin_loaded_capture(target)
    if not target then msg('Specify a character or log in first.', 123); return end
    if running_capture then msg('A lua-list capture is in progress. Try again shortly.', 123); return end
    pending_import = nil
    pending_prune = nil
    msg('Requesting current-client addon list (' .. capture_mode .. ')...')
    issue_loaded_list({target = target, started = false, finished = false, lines = {}})
end

begin_audit = function(source, done)
    local who = current_profile()
    if not who then
        msg('Audit needs a logged-in character.', 123)
        if done then done(false) end
        return false
    end
    if running_capture then
        msg('Audit skipped: a lua-list capture is already running.', 123)
        if done then done(false) end
        return false
    end
    if source == 'manual' then
        msg('Auditing global + ' .. who .. ' using ' .. capture_mode .. ' output.')
    end
    return issue_loaded_list({kind = 'audit', source = source, character = who,
        started = false, finished = false, lines = {}, done = done})
end

-- A live addon reload is NOT a character login. Before issuing any saved
-- profile loads, inspect the running client. Failure is deliberately fail-closed.
local function reconcile_on_reload()
    local who = current_profile()
    if not who or not startup_enabled then return end
    generation = generation + 1
    local token = generation
    coroutine.schedule(function()
        -- Let LuaCore finish addon load and Logger establish its log file.
        coroutine.sleep(0.5)
        if generation ~= token or current_profile() ~= who then return end
        msg('Safe reload: auditing global + ' .. who .. ' before any load requests.')
        begin_audit('reload', function(ok, missing)
            if generation ~= token or current_profile() ~= who then return end
            if not ok then
                msg('Safe reload: no addons loaded because verification was inconclusive. '
                    .. 'Use //am audit or //am apply to load manually.', 123)
                return
            end
            if #missing == 0 then
                msg('Safe reload: all configured addons already running. Nothing to load.')
                return
            end
            local list = missing
            msg(('Safe reload: %d addon(s) missing; only those will be requested.'):format(#list))
            local after
            if verify_enabled then
                after = function()
                    coroutine.schedule(function()
                        coroutine.sleep(3)
                        if current_profile() == who and verify_enabled then
                            begin_audit('startup')
                        end
                    end, 0)
                end
            end
            command_items('load', list, 'Safe reload: missing for ' .. who, 0, after)
        end)
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
        if not raw then msg('Create AddonManager/data/import.txt first.', 123); return end
        candidates = parse_lines(raw)
    else
        msg('Use //am import loaded|init|legacy|file [profile]', 123)
        return
    end
    pending_prune = nil
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
    msg('No changes yet. //am import confirm or //am import cancel.')
end

local function import_command(source, target)
    if source == 'cancel' then pending_import = nil; msg('Import canceled'); return end
    if source == 'confirm' then
        if not pending_import then msg('Nothing awaiting confirmation.', 123); return end
        local p = pending_import
        -- Recheck the current global list at confirmation; global wins for characters.
        local shared = p.source == 'loaded' and p.target ~= 'global'
            and read_profile('global') or {}
        local safe = {}
        for _, addon in ipairs(p.names) do
            if not has_value(shared, addon) then safe[#safe + 1] = addon end
        end
        local combined = combine(read_profile(p.target), safe)
        if write_profile(p.target, combined) then
            msg(('Imported %d entry/entries into %s; saved.'):format(#safe, p.target))
            pending_import = nil
        end
        return
    end
    preview_import(source, target_profile(target))
end

-- Remove profile duplication only after a preview and explicit confirmation.
-- This rewrites a character profile, but never unloads anything.
local function prune_command(arg)
    local choice = arg and arg:lower() or ''
    if choice == 'cancel' then
        pending_prune = nil
        msg('Prune canceled; profile unchanged')
        return
    elseif choice == 'confirm' then
        if not pending_prune then msg('Nothing awaiting prune confirmation.', 123); return end
        local p = pending_prune
        local global_now = read_profile('global')
        local kept, removed = {}, 0
        for _, addon in ipairs(read_profile(p.target)) do
            if has_value(p.duplicates, addon) and has_value(global_now, addon) then
                removed = removed + 1
            else
                kept[#kept + 1] = addon
            end
        end
        if write_profile(p.target, kept) then
            pending_prune = nil
            msg(('Pruned %d redundant entries from %s; nothing unloaded.'):format(removed, p.target))
        end
        return
    end
    local target = target_profile(arg)
    if not target or target == 'global' then
        msg('Use //am prune [character], then //am prune confirm|cancel. Global is never pruned.', 123)
        return
    end
    pending_import = nil
    local global = read_profile('global')
    local duplicates = {}
    for _, addon in ipairs(read_profile(target)) do
        if has_value(global, addon) then duplicates[#duplicates + 1] = addon end
    end
    pending_prune = {target = target, duplicates = duplicates}
    msg(('Prune preview for %s: %d entries already in global. No changes yet.'):format(
        target, #duplicates))
    for _, addon in ipairs(duplicates) do msg('  - ' .. addon, 0) end
    msg('Use //am prune confirm or //am prune cancel.')
end

local function read_options()
    local saved = read_text(data_dir .. 'options.txt') or ''
    for key, value in saved:gmatch('([%w_]+)%s*=%s*([^\r\n]+)') do
        if key == 'delay' then
            local n = tonumber(value)
            if n and n >= 0 and n <= 10 then delay_seconds = n end
        elseif key == 'startup' then
            startup_enabled = trim(value) ~= 'off'
        elseif key == 'verify' then
            verify_enabled = trim(value) ~= 'off'
        elseif key == 'capture' then
            local mode = trim(value):lower()
            if mode == 'chat' or mode == 'console' then capture_mode = mode end
        elseif key == 'stagger' and cluster then
            cluster.gap(trim(value))
        end
    end
end

local function save_options()
    ensure_dirs()
    local f, err = io.open(data_dir .. 'options.txt', 'w')
    if not f then msg('Cannot save options: ' .. tostring(err), 123); return false end
    f:write('startup=', startup_enabled and 'on' or 'off', '\n')
    f:write('delay=', tostring(delay_seconds), '\n')
    f:write('verify=', verify_enabled and 'on' or 'off', '\n')
    f:write('capture=', capture_mode, '\n')
    f:write('stagger=', tostring(cluster.gap()), '\n')
    f:close()
    return true
end

cluster = require('am_cluster')({
    message = msg,
    check = function(addon)
        if not valid_name(addon) or addon == 'addonmanager' or addon == 'addontoggle' or
            addon == 'plugin_manager' then
            return false, 'Invalid or protected addon name: ' .. tostring(addon)
        end
        local installed, scanned = is_installed(addon)
        if not scanned then return false, 'Cannot validate installed addon folders.' end
        if not installed then return false, 'Addon not installed: ' .. addon end
        return true
    end,
    run = function(action, addon)
        if action ~= 'load' and action ~= 'reload' then return false, 'Invalid action.' end
        if not valid_name(addon) or addon == 'addonmanager' or addon == 'addontoggle' or
            addon == 'plugin_manager' then return false, 'Protected addon.' end
        local installed, scanned = is_installed(addon)
        if not scanned or not installed then return false, 'Missing addon: ' .. addon end
        local ok, err = pcall(windower.send_command, 'lua ' .. action .. ' ' .. addon)
        if not ok then return false, tostring(err) end
        requested[addon] = action .. ' requested (unverified)'
        return true
    end,
})

local function dispatch(...)
    local args = {...}
    local verb = (args[1] or ''):lower()
    if verb == 'help' or verb == '' then
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
            windower.send_command('lua unload AddonManager')
        elseif verb == 'unload' and (args[2] or ''):lower() == 'all' then
            local who = current_profile()
            if not who then msg('Log in to use //am unload all', 123); return end
            command_items('unload', combine(read_profile('global'), read_profile(who)),
                'global + ' .. who)
        else
            local p = target_profile(args[2])
            if not p then msg('Specify a character or log in first.', 123); return end
            command_items(verb, read_profile(p), p)
        end
    elseif verb == 'apply' then
        apply_current()
    elseif verb == 'all' then
        cluster.handle(args[2], args[3], args[4])
    elseif verb == 'stagger' then
        local n = cluster.gap(args[2])
        if args[2] and n then save_options() end
    elseif verb == 'audit' then
        begin_audit('manual')
    elseif verb == 'capture' then
        local choice = args[2] and args[2]:lower()
        if not choice then
            msg('Loaded list output: ' .. capture_mode .. ' (//am capture console|chat)')
        elseif choice ~= 'console' and choice ~= 'chat' then
            msg('Use //am capture console|chat.', 123)
        else
            capture_mode = choice
            if save_options() then msg('List capture source: ' .. capture_mode) end
        end
    elseif verb == 'verify' then
        if args[2] ~= 'on' and args[2] ~= 'off' then
            msg('Startup verification: ' .. (verify_enabled and 'on' or 'off') ..
                '. Usage: //am verify on|off')
            return
        end
        verify_enabled = args[2] == 'on'
        if save_options() then msg('Startup verification ' .. args[2]) end
    elseif verb == 'scan' then
        scan_installed((args[2] or ''):lower() == 'all')
    elseif verb == 'import' then
        import_command((args[2] or ''):lower(), args[3])
    elseif verb == 'prune' then
        prune_command(args[2])
    elseif verb == 'delay' then
        if not args[2] then msg(('Current load spacing: %.1f seconds'):format(delay_seconds)); return end
        local seconds = tonumber(args[2])
        if not seconds or seconds < 0 or seconds > 10 then
            msg('Usage: //am delay <0..10 seconds>', 123); return
        end
        delay_seconds = seconds
        if save_options() then msg('Load spacing saved: ' .. tostring(delay_seconds) .. 's') end
    elseif verb == 'startup' then
        if args[2] ~= 'on' and args[2] ~= 'off' then
            msg('Startup is ' .. (startup_enabled and 'on' or 'off') ..
                '. Usage: //am startup on|off'); return
        end
        startup_enabled = args[2] == 'on'
        if save_options() then msg('Automatic profile loading: ' .. args[2]) end
    elseif verb == 'status' then
        local who = current_profile() or '(character not logged in)'
        msg('v' .. _addon.version .. ' | character: ' .. who ..
            ' | startup: ' .. (startup_enabled and 'on' or 'off') ..
            ' | spacing: ' .. tostring(delay_seconds) .. 's' ..
            ' | verify: ' .. (verify_enabled and 'on' or 'off') ..
            ' | capture: ' .. capture_mode) 
        cluster.status()
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
        cluster.cancel('manager restart')
        windower.send_command('lua reload AddonManager')
    else
        msg('Unknown command: ' .. verb, 123)
        print_help()
    end
end

windower.register_event('addon command', dispatch)

windower.register_event('load', function()
    ensure_dirs()
    read_options()
    current_character = player_name()
    if current_character and startup_enabled then
        reconcile_on_reload()
    end
end)

windower.register_event('login', function(name)
    current_character = normal(name) or player_name()
    generation = generation + 1
    if current_character and startup_enabled then apply_current(3, true) end
end)

windower.register_event('logout', function()
    cluster.cancel('logout')
    generation = generation + 1
    current_character = nil
    pending_import = nil
    pending_prune = nil
    running_capture = nil
end)

windower.register_event('unload', function()
    cluster.cancel('manager unloaded')
    generation = generation + 1
    running_capture = nil
end)