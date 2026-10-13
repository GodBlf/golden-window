# golden-window

一键安装或复用 Hammerspoon，并配置最大尺寸、居中的 **1.618:1 黄金比例窗口**。适用于 macOS，无需 Python；可从 zsh 或 Bash 终端运行。

## 背景

为了美化 Mac 窗口，让桌面上的窗口统一成黄金比例矩形，也方便配合台前调度（Stage Manager）使用。没有什么实用价值，纯粹是看着舒服——just for fun。

## 安装

把整个项目复制到 Mac，然后执行：

```bash
bash ~/Projects/golden-window/install.sh
```

已有 Hammerspoon 时跳过下载；否则执行 `brew install --cask hammerspoon`。如未安装 Homebrew，请先按 [Homebrew 官网](https://brew.sh/)的指引安装，再运行脚本。

首次使用，在 **系统设置 → 隐私与安全性 → 辅助功能** 中开启 Hammerspoon。列表中没有它时，添加 `/Applications/Hammerspoon.app`（或用户 Applications 中实际安装的位置）。授权仍未生效时退出并重新打开 Hammerspoon。

点击菜单栏 **1.618:1**，选择 **1.618:1 · 最大尺寸并居中**。安装过程不会移动窗口。没有快捷键，也没有恢复选项。

## 行为与配置

每个普通可见窗口使用各自显示器的可用区域，扣除菜单栏和 Dock，按 `宽度 = min(可用宽度, 可用高度 × 1.618)` 计算最大黄金矩形并居中。比例针对包含标题栏的窗口外框，整数取整可能造成微小误差。窗口允许重叠；跳过全屏、非普通窗口，不处理其他 Spaces 或最小化窗口。应用自身的尺寸限制可能使部分窗口无法达到目标，菜单栏选项会显示调整结果提示。

脚本部署 `~/.hammerspoon/golden-window.lua`，并在 `init.lua` 中加入一次：

```lua
goldenWindow = require("golden-window")
```

修改前将原文件备份到 `~/.hammerspoon/backups/`。重复安装不重复添加加载语句。保留其他配置和快捷键；仅自动迁移与本项目已确认的旧版内联实现完全一致的代码块，其余冲突会停止，要求先手动检查。已有模块内容与项目不同也会停止。符号链接配置不会被覆盖。

运行中的 Hammerspoon 有可用 `hs` IPC 时会重载并核实菜单名称；没有 IPC 时，请在 Hammerspoon 菜单点击 **Reload Config**。无需为此启用 IPC。新的安装会启动 Hammerspoon。若你自行设置了 Hammerspoon 的其他配置目录，可用 `GOLDEN_WINDOW_CONFIG_DIR=/实际目录 bash install.sh`，但脚本不会替你改变 Hammerspoon 的配置目录。

## 扩展其他比例

当前只提供 1.618:1。以后有需要可在项目 `golden-window.lua` 的 `menuItems` 中同理加入：

```lua
{title = "16:9 · 最大尺寸并居中", fn = function() applyLayout(16 / 9, "16:9") end},
```

同时把 `selectedRatio` 的有效值判断改成允许 `1.618:1` 和 `16:9`。已有 `selectRatio(label)` 会让菜单栏名称随选择切换，并保存上次选择。修改项目或已部署的模块前先备份；安装器会拒绝覆盖不同内容的现有模块，需要自行确认后移开旧模块，再运行安装器。
