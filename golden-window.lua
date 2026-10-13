-- Center all ordinary visible windows at the largest size for the chosen ratio.
-- Screen work areas exclude the menu bar and Dock.
local ratioMenu = hs.menubar.new()
local selectedRatio = hs.settings.get("windowRatio.selected") or "1.618:1"
if selectedRatio ~= "1.618:1" then
    selectedRatio = "1.618:1"
end

local function selectRatio(label)
    selectedRatio = label
    hs.settings.set("windowRatio.selected", label)
    if ratioMenu then ratioMenu:setTitle(label) end
end

local function applyLayout(ratio, label)
    selectRatio(label)
    if not hs.accessibilityState() then
        hs.alert.show("请先在系统设置的辅助功能中授权 Hammerspoon")
        return
    end
    local changed, skipped = 0, 0
    for _, window in ipairs(hs.window.visibleWindows()) do
        local ok, result = pcall(function()
            if not window:isStandard() or window:isFullScreen() then return false end
            local screen = window:screen()
            if not screen then return false end
            local area = screen:frame()
            local width = math.floor(math.min(area.w, area.h * ratio))
            local height = math.floor(width / ratio + 0.5)
            local target = {
                x = area.x + (area.w - width) / 2,
                y = area.y + (area.h - height) / 2,
                w = width,
                h = height,
            }
            window:setFrame(target, 0)
            local actual = window:frame()
            return math.abs(actual.w - target.w) <= 2
                and math.abs(actual.h - target.h) <= 2
                and math.abs(actual.x - target.x) <= 2
                and math.abs(actual.y - target.y) <= 2
        end)
        if ok and result then
            changed = changed + 1
        else
            skipped = skipped + 1
        end
    end
    hs.alert.show(string.format("%s：%d 个窗口已调整，%d 个受限制或跳过", label, changed, skipped))
end

local menuItems = {
    {title = "1.618:1 · 最大尺寸并居中", fn = function() applyLayout(1.618, "1.618:1") end},
}
if ratioMenu then
    ratioMenu:setTitle(selectedRatio)
    ratioMenu:setTooltip("点击将窗口设为最大的居中黄金矩形")
    ratioMenu:setMenu(menuItems)
end

-- Keep the menu alive; no keyboard shortcuts or restore action.
return { menu = ratioMenu, menuItems = menuItems, selectRatio = selectRatio }
