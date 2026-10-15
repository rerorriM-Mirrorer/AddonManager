-- Mock-Windower smoke tests for Lua 5.1; no FFXI installation needed.
_addon = {}
local events, commands, chats = {}, {}, {}
local who = 'Myrr'

package.preload['chat'] = function()
    string.color = function(self) return self end
    return {}
end

local addon_names = {
    'AddonToggle', 'BarFiller', 'EquipViewer', 'ConsoleBGPlus', 'EnemyBar2'
}

windower = {
    addon_path = './tmp_pm/',
    windower_path = './tmp_windower/',
    add_to_chat = function(_, text) chats[#chats + 1] = text end,
    send_command = function(command) commands[#commands + 1] = command end,
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

os.execute('mkdir -p tmp_pm/data/profiles tmp_windower/scripts tmp_windower/addons/plugin_manager/data')
dofile('AddonToggle.lua')
assert(type(events.load) == 'function', 'load event not registered')
assert(type(events.login) == 'function', 'login event not registered')
assert(type(events['addon command']) == 'function', 'addon command handler missing')

local pm = events['addon command']
events.load()
assert(count_command('alias at lua c AddonToggle legacy-toggle') == 1, 'legacy alias missing')
pm('add', 'global', 'EquipViewer')
assert(contents('tmp_pm/data/profiles/global.txt') == 'equipviewer\n', 'global list not saved')
pm('add', 'global', 'EquipViewer')
assert(contents('tmp_pm/data/profiles/global.txt') == 'equipviewer\n', 'duplicate entry added')
pm('add', 'Myrr', 'BarFiller')
assert(contents('tmp_pm/data/profiles/myrr.txt') == 'barfiller\n', 'character list not saved')

pm('apply')
assert(count_command('lua load equipviewer') >= 1, 'global addon not loaded')
assert(count_command('lua load barfiller') >= 1, 'character addon not loaded')

pm('add', 'Cioara', 'EnemyBar2')
pm('load', 'Cioara')
assert(count_command('lua load enemybar2') >= 1, 'named profile not loaded')
assert(contents('tmp_pm/data/profiles/myrr.txt') == 'barfiller\n',
    'named profile changed currently logged in profile')

pm('remove', 'Myrr', 'BarFiller')
assert(contents('tmp_pm/data/profiles/myrr.txt') == '', 'removed entry still in saved profile')

file('tmp_windower/scripts/init.txt',
    'lua load ConsoleBGPlus\nlua unload EquipViewer\nlua l BarFiller\n')
pm('import', 'init', 'global')
assert(contents('tmp_pm/data/profiles/global.txt') == 'equipviewer\n', 'preview changed saved list')
pm('import', 'confirm')
local updated = contents('tmp_pm/data/profiles/global.txt')
assert(updated:find('consolebgplus', 1, true), 'init import did not save first addon')
assert(updated:find('barfiller', 1, true), 'init import did not save shorthand addon')
assert(not updated:find('lua', 1, true), 'invalid import contents')

file('tmp_windower/addons/plugin_manager/data/settings.xml',
    '<settings><global><addon>EnemyBar2</addon></global>' ..
    '<Cioara><plugin>Timers</plugin><addon>EquipViewer</addon></Cioara></settings>')
pm('import', 'legacy', 'Cioara')
pm('import', 'confirm')
assert(contents('tmp_pm/data/profiles/cioara.txt'):find('equipviewer', 1, true),
    'legacy XML import not saved')

pm('legacy-toggle')
assert(count_command('lua unload barfiller; wait 0.2; lua unload equipviewer') >= 1,
    'legacy toggle broken')

pm('startup', 'off')
pm('delay', '0.5')
assert(contents('tmp_pm/data/options.txt'):find('delay=0.5', 1, true),
    'settings not saved')
events.logout()
who = 'Cioara'
events.login('Cioara')
print('AddonToggle mock smoke test: PASS (' .. #commands .. ' Windower commands)')
