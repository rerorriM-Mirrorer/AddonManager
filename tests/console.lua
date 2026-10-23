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
