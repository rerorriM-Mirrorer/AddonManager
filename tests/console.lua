-- Mock filesystem coverage for am_console. No Windower or FFXI needed.
local module = dofile('am_console.lua')
os.execute('mkdir -p tmp_windower')
local log = 'tmp_windower/console.log'
local function write(content)
    local f = assert(io.open(log, 'wb'))
    f:write(content)
    f:close()
end
local function append(content)
    local f = assert(io.open(log, 'ab'))
    f:write(content)
    f:close()
end
write('Old data\nCurrently loaded addons:\n  NotARealCurrentAddon\n')
local shot, error_message = module.begin('tmp_windower/', 'Cioara')
assert(shot and not error_message)
local commands = module.commands(shot)
assert(#commands == 3 and commands[2] == 'lua list console')
assert(shot.begin_marker:find('AddonManager | Cioara | Checking loaded addons', 1, true),
    'console begin marker should be readable')
assert(shot.end_marker:find('AddonManager | Cioara | Finished listing addons', 1, true),
    'console end marker should be readable')
assert(#shot.begin_marker < 90 and #shot.end_marker < 90,
    'marker exceeded a reasonable console width')
assert(commands[1] == 'console_echo "' .. shot.begin_marker .. '"' and
    commands[3] == 'console_echo "' .. shot.end_marker .. '"',
    'console_echo should use the same friendly marker as the parser')

local lines, reason = module.finish(shot)
assert(lines == nil and reason, 'stale data treated as current capture')
append(shot.begin_marker .. '\nCurrently loaded addons:\n' ..
    '  Equipviewer\n  AddonManager\n' .. shot.end_marker .. '\n')
lines, reason = module.finish(shot)
assert(lines and #lines == 2 and lines[1] == 'Equipviewer' and
    lines[2] == 'AddonManager', 'fresh bounded console list not captured')
-- A second captured response contains noisy GilFinder stack errors interleaved
-- with the legitimate list. Recognized errors can be ignored, not promoted to
-- addon names or allowed to invalidate the entire audit.
local noisy = assert(module.begin('tmp_windower/', 'Cioara'))
append(noisy.begin_marker .. '\nCurrently loaded addons:\n' ..
    '  Equipviewer\n' ..
    '[Lua] gilfinder/glint.lua:30: attempt to index field (a nil value)\n' ..
    'stack traceback:\n' ..
    '  addons/gilfinder/glint.lua:30: in function render\n' ..
    '  AddonManager\n' .. noisy.end_marker .. '\n')
lines, reason = module.finish(noisy)
assert(lines and #lines == 2 and reason == 3,
    'interleaved Lua errors should not break a complete list')
local suspicious = assert(module.begin('tmp_windower/', 'Cioara'))
append(suspicious.begin_marker .. '\nCurrently loaded addons:\n' ..
    '  Equipviewer\nUNRECOGNIZED CONSOLE MESSAGE\n' ..
    '  AddonManager\n' .. suspicious.end_marker .. '\n')
lines, reason = module.finish(suspicious)
assert(lines == nil and reason:find('UNRECOGNIZED CONSOLE MESSAGE', 1, true),
    'unknown interleaved text was silently accepted')
-- Regression from Killala's live 2026-10-22 log. LuaCore writes
-- "20:58:48 >   autoex" in console.log: the clock/prompt must not be
-- interpreted as part of the addon name or as unknown console output.
local timed = assert(module.begin('tmp_windower/', 'Killala'))
append('20:58:48 > ' .. timed.begin_marker .. '\n' ..
    '20:58:48 > Currently loaded addons:\n' ..
    '20:58:48 >   autoex\n' ..
    '20:58:48 >   Battle Stations\n' ..
    '20:58:48 >   AddonManager\n' ..
    '20:58:48 > ' .. timed.end_marker .. '\n')
lines, reason = module.finish(timed)
assert(lines and #lines == 3 and lines[1] == 'autoex' and
    lines[2] == 'Battle Stations' and lines[3] == 'AddonManager',
    'time-stamped native console list was not captured')

-- Native console.log wraps echo content in literal double quotes, too.
-- This regression reproduces the exact header/row/quote structure of the
-- 20:58:48 live Killala console capture rather than a quote-free mock.
local quoted = assert(module.begin('tmp_windower/', 'Killala'))
append('20:58:48 > "' .. quoted.begin_marker .. '"\n' ..
    '20:58:48 > Currently loaded addons:\n' ..
    '20:58:48 >   autoex\n' ..
    '20:58:48 >   AutoJoin\n' ..
    '20:58:48 >   Battle Stations\n' ..
    '20:58:48 >   gilfinder\n' ..
    '20:58:48 >   AddonManager\n' ..
    '20:58:48 > "' .. quoted.end_marker .. '"\n')
lines, reason = module.finish(quoted)
assert(lines and #lines == 5 and lines[1] == 'autoex' and
    lines[4] == 'gilfinder' and lines[5] == 'AddonManager',
    'real console timestamp + quote format should verify correctly')

-- Interleaving from a different client must be rejected even with readable
-- markers and valid loaded-addon names around that client's output.
local other = assert(module.begin('tmp_windower/', 'Franklet'))
append('20:58:58 > "' .. other.begin_marker .. '"\n' ..
    '20:58:58 > Currently loaded addons:\n' ..
    '20:58:58 >   autoex\n' ..
    '20:58:58 > "AddonManager | Killala | Checking loaded addons (#5)"\n' ..
    '20:58:58 >   AddonManager\n' ..
    '20:58:58 > "' .. other.end_marker .. '"\n')
lines, reason = module.finish(other)
assert(lines == nil and reason:find('interleaved', 1, true),
    'foreign readable marker was not rejected')

-- Likewise ignore timestamped *recognized* Lua errors without treating
-- arbitrary timestamped text as an addon name.
local timed_noisy = assert(module.begin('tmp_windower/', 'Killala'))
append('20:58:58 > ' .. timed_noisy.begin_marker .. '\n' ..
    '20:58:58 > Currently loaded addons:\n' ..
    '20:58:58 >   autoex\n' ..
    '20:58:58 > [Lua] gilfinder/glint.lua:30: attempt to index field (nil)\n' ..
    '20:58:58 >   AddonManager\n' ..
    '20:58:58 > ' .. timed_noisy.end_marker .. '\n')
lines, reason = module.finish(timed_noisy)
assert(lines and #lines == 2 and reason == 1,
    'timestamped Lua stack error contaminated native list')

local timed_foreign = assert(module.begin('tmp_windower/', 'Killala'))
append('20:58:58 > ' .. timed_foreign.begin_marker .. '\n' ..
    '20:58:58 > Currently loaded addons:\n' ..
    '20:58:58 >   autoex\n' ..
    '20:58:58 > UNEXPECTED CHATTER\n' ..
    '20:58:58 >   AddonManager\n' ..
    '20:58:58 > ' .. timed_foreign.end_marker .. '\n')
lines, reason = module.finish(timed_foreign)
assert(lines == nil and reason:find('UNEXPECTED CHATTER', 1, true),
    'timestamped foreign console line was treated as an addon')

-- Same filesystem file can include other clients. Interleaving must fail.
local interleaved = assert(module.begin('tmp_windower/', 'Myrr'))
append(interleaved.begin_marker .. '\nCurrently loaded addons:\n' ..
    '  Equipviewer\nAM_LIST_BEGIN_OTHER_CLIENT\n' ..
    '  AddonManager\n' .. interleaved.end_marker .. '\n')
lines = module.finish(interleaved)
assert(lines == nil, 'interleaved client output accepted')
-- An incomplete response is not sufficient to authorize a load.
local incomplete = assert(module.begin('tmp_windower/', 'Cioara'))
append(incomplete.begin_marker .. '\nCurrently loaded addons:\n  Equipviewer\n')
lines = module.finish(incomplete)
assert(lines == nil, 'incomplete console output accepted')
local empty = assert(module.begin('tmp_windower/', 'Cioara'))
append(empty.begin_marker .. '\nCurrently loaded addons:\n' .. empty.end_marker .. '\n')
lines = module.finish(empty)
assert(lines == nil, 'header-only response accepted')
-- No new output after watermark is not accepted.
local no_growth = assert(module.begin('tmp_windower/', 'Cioara'))
lines = module.finish(no_growth)
assert(lines == nil, 'old marker accepted')
-- Missing log file fails closed and never turns logging on itself.
os.remove(log)
local missing, why = module.begin('tmp_windower/', 'Cioara')
assert(missing == nil and why:find('console.log'), 'missing log not detected')
print('AddonManager console capture: PASS')
