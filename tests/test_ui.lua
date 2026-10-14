-- Run from the project root: luajit tests/test_ui.lua
-- Can also run inside Hammerspoon; its real windows and configuration are untouched.
local realHs = hs
local modulePath = (arg and arg[1]) or "golden-window.lua"
local config = os.tmpname()
os.remove(config)
assert(os.execute('mkdir -p "' .. config .. '"'))
local languagePath = config .. "/.golden-window-language"
local realIo = io
local actualMenu
local assertions = 0
local function check(value)
    assert(value)
    assertions = assertions + 1
end
local function run(saved, expected, unreadable)
    if saved then
        local file = assert(realIo.open(languagePath, "w"))
        file:write(saved)
        file:close()
    else
        os.remove(languagePath)
    end
    local alert, title, tooltip, items, settings
    local allowed = true
    local menu = {}
    if realHs then actualMenu = assert(realHs.menubar.new()) end
    function menu:setTitle(value) title = value; if actualMenu then actualMenu:setTitle(value) end end
    function menu:setTooltip(value) tooltip = value; if actualMenu then actualMenu:setTooltip(value) end end
    function menu:setMenu(value) items = value; if actualMenu then actualMenu:setMenu(value) end end
    local target
    local ordinary = {
        isStandard = function() return true end,
        isFullScreen = function() return false end,
        screen = function() return {frame = function() return {x=100, y=40, w=1400, h=900} end} end,
        setFrame = function(_, value, duration) check(duration == 0); target = value end,
        frame = function() return target end,
    }
    local nonstandard = {isStandard = function() return false end}
    local fullscreen = {isStandard = function() return true end, isFullScreen = function() return true end}
    local constrained = {
        isStandard = ordinary.isStandard, isFullScreen = ordinary.isFullScreen,
        screen = ordinary.screen, setFrame = function() end,
        frame = function() return {x=0, y=0, w=100, h=100} end,
    }
    local mockHs = {
        configdir = config,
        menubar = {new = function() return menu end},
        settings = {get = function() return "invalid ratio" end, set = function(_, value) settings=value end},
        accessibilityState = function() return allowed end,
        alert = {show = function(value) alert=value end},
        window = {visibleWindows = function() return {ordinary, nonstandard, fullscreen, constrained} end},
    }
    local env = setmetatable({hs = mockHs, io = unreadable and {open = function() return nil end} or realIo}, {__index = _G})
    local chunk
    if setfenv then chunk = assert(loadfile(modulePath)); setfenv(chunk, env)
    else chunk = assert(loadfile(modulePath, "t", env)) end
    local module = chunk()
    check(module.language == expected)
    check(title == "1.618:1")
    check(target == nil) -- Loading must never move windows.
    check(items == module.menuItems and #items == 1)
    check(items[1].title == (expected == 'en' and '1.618:1 · Maximize and center' or '1.618:1 · 最大尺寸并居中'))
    check(tooltip == (expected == 'en' and 'Click to maximize and center windows at the golden ratio' or '点击将窗口设为最大的居中黄金矩形'))
    allowed = false
    items[1].fn()
    check(target == nil)
    check(alert == (expected == 'en' and 'Enable Hammerspoon in System Settings → Privacy & Security → Accessibility first' or '请先在系统设置的辅助功能中授权 Hammerspoon'))
    allowed = true
    items[1].fn()
    check(target.w == 1400 and target.h == 865 and target.x == 100 and target.y == 57.5)
    check(settings == "1.618:1")
    check(alert == (expected == 'en' and '1.618:1: 1 windows adjusted, 3 constrained or skipped' or '1.618:1：1 个窗口已调整，3 个受限制或跳过'))
    if actualMenu then actualMenu:delete(); actualMenu = nil end
end
local ok, err = pcall(function()
    run(nil, 'en')
    run('en\n', 'en')
    run('zh-CN\n', 'zh-CN')
    run('zh-CN', 'zh-CN')
    run('zh-CN\n\n', 'zh-CN')
    run('fr\n', 'en')
    run('zh-CN\nextra', 'en')
    run('', 'en')
    run('zh-CN\n', 'en', true)
end)
if actualMenu then actualMenu:delete() end
os.remove(languagePath)
os.execute('rmdir "' .. config .. '"')
assert(ok, err)
print('UI checks passed: ' .. assertions .. ' assertions' .. (realHs and ' (Hammerspoon)' or ' (Lua)'))
