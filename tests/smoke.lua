-- Mock-Windower smoke tests for Lua 5.1; no FFXI installation needed.
_addon = {}
local events, commands, chats = {}, {}, {}
local who = 'Myrr'
local simulate_list = true

package.preload['chat'] = function()
    string.color = function(self) return self end
    string.strip_colors = function(self) return self end
    return {}
end

local addon_names = {
    'AddonManager', 'BarFiller', 'EquipViewer', 'ConsoleBGPlus', 'EnemyBar2',
    'BattleStations', 'JobChange'
}

windower = {
    addon_path = './tmp_am/',
    windower_path = './tmp_windower/',
    add_to_chat = function(_, text) chats[#chats + 1] = text end,
    send_command = function(command)
        commands[#commands + 1] = command
        if command == 'lua list' and simulate_list then
            local lines = {
                'Currently loaded addons:',
                '  Equipviewer',
                '  Battle Stations',
                '  Job Change',
                '  plugin_manager',
                '  Missing Fake Addon',
            }
            for _, line in ipairs(lines) do
                events['incoming text']('', line, 0, 0, false)
            end
        end
    end,
    register_event = function(event, cb) events[event] = cb end,
    get_dir = function() return addon_names end,
    dir_exists = function() return true end,
    file_exists = function(path)
        for _, name in ipairs(addon_names) do
            if path:lower():find(('/' .. name .. '.lua'):lower(), 1, true) then
                return true
            end
        end
        return false
    end,
    create_dir = function() return true end,
    ffxi = {get_player = function() return {name = who} end},
}

coroutine.schedule = function(cb) cb() end
coroutine.sleep = function() end

local function file(path, text)
    local f = assert(io.open(path, 'w'))
    f:write(text)
    f:close()
end

local function contents(path)
    local f = assert(io.open(path, 'r'))
    local str = f:read('*a')
    f:close()
    return str
end

local function count_command(needle)
    local n = 0
    for _, command in ipairs(commands) do
        if command == needle then n = n + 1 end
    end
    return n
end

os.execute('mkdir -p tmp_am/data/profiles tmp_windower/scripts tmp_windower/addons/plugin_manager/data')
dofile('AddonManager.lua')
assert(type(events.load) == 'function', 'load event not registered')
assert(type(events.login) == 'function', 'login event not registered')
assert(type(events['addon command']) == 'function', 'addon command handler missing')

local am = events['addon command']
events.load()
assert(count_command('alias at lua c AddonManager legacy-toggle') == 0, 'obsolete alias unexpectedly created')
assert(count_command('lua unload barfiller; wait 0.2; lua unload equipviewer') == 0,
    'former overlay toggle still registered')
am('add', 'global', 'EquipViewer')
assert(contents('tmp_am/data/profiles/global.txt') == 'equipviewer\n', 'global list not saved')
am('add', 'global', 'EquipViewer')
assert(contents('tmp_am/data/profiles/global.txt') == 'equipviewer\n', 'duplicate entry added')
am('add', 'Myrr', 'BarFiller')
assert(contents('tmp_am/data/profiles/myrr.txt') == 'barfiller\n', 'character list not saved')

am('apply')
local count_before_all = count_command('lua load equipviewer')
am('load', 'all')
assert(count_command('lua load equipviewer') == count_before_all + 1, 'load all did not apply global profile')
assert(count_command('lua load equipviewer') >= 1, 'global addon not loaded')
assert(count_command('lua load barfiller') >= 1, 'character addon not loaded')

am('add', 'Cioara', 'EnemyBar2')
am('load', 'Cioara')
assert(count_command('lua load enemybar2') >= 1, 'named profile not loaded')
assert(contents('tmp_am/data/profiles/myrr.txt') == 'barfiller\n',
    'named profile changed currently logged in profile')

am('remove', 'Myrr', 'BarFiller')
assert(contents('tmp_am/data/profiles/myrr.txt') == '', 'removed entry still in saved profile')

file('tmp_windower/scripts/init.txt',
    'lua load ConsoleBGPlus\nlua unload EquipViewer\nlua l BarFiller\n')
am('import', 'init', 'global')
assert(contents('tmp_am/data/profiles/global.txt') == 'equipviewer\n', 'preview changed saved list')
am('import', 'confirm')
local updated = contents('tmp_am/data/profiles/global.txt')
assert(updated:find('consolebgplus', 1, true), 'init import did not save first addon')
assert(updated:find('barfiller', 1, true), 'init import did not save shorthand addon')
assert(not updated:find('lua', 1, true), 'invalid import contents')

file('tmp_windower/addons/plugin_manager/data/settings.xml',
    '<settings><global><addon>EnemyBar2</addon></global>' ..
    '<Cioara><plugin>Timers</plugin><addon>EquipViewer</addon></Cioara></settings>')
am('import', 'legacy', 'Cioara')
am('import', 'confirm')
assert(contents('tmp_am/data/profiles/cioara.txt'):find('equipviewer', 1, true),
    'legacy XML import not saved')

-- Loaded-addon list is obtained from the SAME incoming-text event used
-- by Windower's Logger addon, and mapped to actual folder names.
am('add', 'global', 'JobChange')
am('import', 'loaded', 'Cioara')
local before_live = contents('tmp_am/data/profiles/cioara.txt')
assert(not before_live:find('battlestations', 1, true),
    'loaded snapshot was imported before confirmation')
am('import', 'confirm')
local live = contents('tmp_am/data/profiles/cioara.txt')
assert(live:find('battlestations', 1, true), 'spaced display name not resolved')
assert(not live:find('jobchange', 1, true), 'global addon was incorrectly added to character profile')
assert(not live:find('plugin_manager', 1, true), 'manager imported unsafely')
assert(not live:find('missing', 1, true), 'unknown addon imported unsafely')
-- Cleanup previews redundancy, never edits until explicit confirmation.
local before_prune = contents('tmp_am/data/profiles/cioara.txt')
am('prune', 'Cioara')
assert(contents('tmp_am/data/profiles/cioara.txt') == before_prune,
    'prune preview incorrectly edited profile')
am('prune', 'confirm')
local cleaned = contents('tmp_am/data/profiles/cioara.txt')
assert(not cleaned:find('equipviewer', 1, true), 'prune kept globally-covered addon')
assert(cleaned:find('battlestations', 1, true), 'prune lost character-specific addon')
am('prune', 'Cioara')
am('prune', 'cancel')
simulate_list = false
am('import', 'loaded', 'Myrr')
am('import', 'confirm')
assert(contents('tmp_am/data/profiles/myrr.txt') == '',
    'missing live output changed profile')

am('startup', 'off')
am('delay', '0.5')
assert(contents('tmp_am/data/options.txt'):find('delay=0.5', 1, true),
    'settings not saved')
events.logout()
who = 'Cioara'
local prior = count_command('lua load enemybar2')
events.login('Cioara')
assert(count_command('lua load enemybar2') == prior, 'startup off still loaded addon')
am('startup', 'on')
events.logout()
events.login('Cioara')
assert(count_command('lua load enemybar2') == prior + 1,
    'actual login did not automatically load character profile')
local global_before = count_command('lua load equipviewer')
assert(global_before >= 1, 'global profile not loaded')
am('unload', 'manager')
assert(count_command('lua unload AddonManager') >= 1, 'explicit manager unload missing')
print('AddonManager mock smoke test: PASS (' .. #commands .. ' Windower commands)')
