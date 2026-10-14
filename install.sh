#!/bin/bash
# Compatible with macOS Bash 3.2. No Python or GNU utilities required.
set -euo pipefail

# Keep the language prompt bilingual so it is readable before a choice is made.
config_dir="${GOLDEN_WINDOW_CONFIG_DIR:-$HOME/.hammerspoon}"
init_file="$config_dir/init.lua"
module_file="$config_dir/golden-window.lua"
language_file="$config_dir/.golden-window-language"
language=en
message() {
    local english="$1" chinese="$2"
    shift 2
    if [ "$language" = zh-CN ]; then printf "$chinese\n" "$@"; else printf "$english\n" "$@"; fi
}
fail_message() { message "$@" >&2; exit 1; }
if [ ! -L "$language_file" ] && [ -f "$language_file" ]; then
    saved_language=$(cat "$language_file")
    case "$saved_language" in en|zh-CN) language="$saved_language" ;; esac
fi
if [ "${GOLDEN_WINDOW_LANG+x}" = x ]; then
    case "$GOLDEN_WINDOW_LANG" in
        en|zh-CN) language="$GOLDEN_WINDOW_LANG" ;;
        *) fail_message 'Error: GOLDEN_WINDOW_LANG must be en or zh-CN.' '错误：GOLDEN_WINDOW_LANG 必须为 en 或 zh-CN。' ;;
    esac
elif [ -t 0 ]; then
    while :; do
        printf 'Language / 语言: 1) English  2) 简体中文 [%s]: ' "$language"
        choice=''
        if ! IFS= read -r choice; then printf '\n'; break; fi
        case "$choice" in
            '') break ;;
            1) language=en; break ;;
            2) language=zh-CN; break ;;
            *) printf 'Please enter 1 or 2 / 请输入 1 或 2。\n' ;;
        esac
    done
fi
[ "$(uname -s)" = Darwin ] || fail_message 'Error: This script only supports macOS.' '错误：此脚本只支持 macOS。'
project_dir=$(cd "$(dirname "$0")" && pwd)
source_lua="$project_dir/golden-window.lua"
[ -f "$source_lua" ] || fail_message 'Error: The bundled golden-window.lua is missing.' '错误：缺少随附的 golden-window.lua。'
# Custom config_dir is useful for an explicitly configured Hammerspoon directory.
[ ! -L "$init_file" ] && [ ! -L "$module_file" ] && [ ! -L "$language_file" ] || fail_message 'Error: A configuration file is a symbolic link. Check its target manually; the installer will not overwrite it.' '错误：配置文件是符号链接，请先手动确认目标，脚本不会覆盖。'

app_path=''
for candidate in /Applications/Hammerspoon.app "$HOME/Applications/Hammerspoon.app"; do
    if [ -d "$candidate" ]; then app_path="$candidate"; break; fi
done
if [ -z "$app_path" ]; then
    brew_cmd=$(command -v brew || true)
    if [ -z "$brew_cmd" ]; then
        for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
            if [ -x "$candidate" ]; then brew_cmd="$candidate"; break; fi
        done
    fi
    [ -n "$brew_cmd" ] || fail_message 'Error: Hammerspoon and Homebrew were not found. Install Homebrew using the official instructions at https://brew.sh/ and run again.' '错误：未找到 Hammerspoon 和 Homebrew。请先按 https://brew.sh/ 的官方指引安装 Homebrew，然后重新运行。'
    message 'Installing Hammerspoon with Homebrew…' '通过 Homebrew 安装 Hammerspoon…'
    "$brew_cmd" install --cask hammerspoon || fail_message 'Error: Hammerspoon installation failed; configuration has not been modified.' '错误：Hammerspoon 安装失败，未修改配置。'
    for candidate in /Applications/Hammerspoon.app "$HOME/Applications/Hammerspoon.app"; do
        if [ -d "$candidate" ]; then app_path="$candidate"; break; fi
    done
    [ -n "$app_path" ] || fail_message 'Error: Homebrew succeeded, but Hammerspoon was not found in Applications; configuration has not been modified.' '错误：Homebrew 已返回成功，但未在 Applications 目录找到 Hammerspoon，未修改配置。'
else
    message 'Hammerspoon is already installed; skipping download: %s' '已安装 Hammerspoon，跳过下载：%s' "$app_path"
fi

scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/golden-window.XXXXXX")
lock_dir=''
cleanup() {
    rm -rf "$scratch_dir"
    if [ -n "$lock_dir" ]; then rmdir "$lock_dir" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$config_dir"
if ! mkdir "$config_dir/.golden-window-install.lock" 2>/dev/null; then
    fail_message 'Error: Another installer or stale lock was detected: %s' '错误：检测到其他安装进程或遗留锁：%s' "$config_dir/.golden-window-install.lock"
fi
lock_dir="$config_dir/.golden-window-install.lock"
[ ! -L "$init_file" ] && [ ! -L "$module_file" ] && [ ! -L "$language_file" ] || fail_message 'Error: A configuration file is a symbolic link; installation stopped.' '错误：配置文件是符号链接，停止安装。'

original="$scratch_dir/original.lua"
if [ -f "$init_file" ]; then cp -p "$init_file" "$original"; else : > "$original"; fi
cleaned="$scratch_dir/cleaned.lua"
cp "$original" "$cleaned"

# Only migrate the exact inline implementation verified on the original Mac.
# Keep all text outside that block, including require("hs.ipc").
legacy_start='-- Center all ordinary visible windows at the largest size for the chosen ratio.'
legacy_end='ratioWindow = { menu = ratioMenu, menuItems = menuItems, selectRatio = selectRatio }'
if grep -Fq -- "$legacy_start" "$original"; then
    awk -v start="$legacy_start" -v end="$legacy_end" '
        $0 == start { inside = 1 }
        inside { print }
        inside && $0 == end { inside = 0 }
    ' "$original" > "$scratch_dir/legacy.lua"
    legacy_hash=$(shasum -a 256 "$scratch_dir/legacy.lua" | awk '{print $1}')
    [ "$legacy_hash" = '5f68fba0234285f4c840afde8e27529fc6f82a5b78f6c1e78feb57cf415de368' ] || fail_message 'Error: Unrecognized legacy inline window configuration. Remove it manually and run again; original files have not been modified.' '错误：发现旧版内联窗口配置，但内容无法确认。请手动移除旧功能后重新运行；原文件未修改。'
    awk -v start="$legacy_start" -v end="$legacy_end" '
        $0 == start { inside = 1 }
        !inside { print }
        inside && $0 == end { inside = 0 }
    ' "$original" > "$cleaned"
    message 'Recognized legacy inline configuration; migrating to a standalone module.' '已识别旧版内联配置，将迁移为独立模块。'
fi

# Collapse only the exact supported loader. Reject ambiguous manual variants.
awk '{ line=$0; gsub(/^[ \t]+|[ \t]+$/, "", line); if (line != "goldenWindow = require(\"golden-window\")") print }' "$cleaned" > "$scratch_dir/unrelated.lua"
if grep -Eq 'golden-window|ratioWindow|ratioMenu|applyGoldenLayout|undoGoldenLayout|goldenMenu|windowRatio\.selected' "$scratch_dir/unrelated.lua"; then
    fail_message 'Error: Ambiguous window configuration or loader. Check init.lua; original files have not been modified.' '错误：发现不能明确迁移的窗口配置或加载语句。请检查 init.lua；原文件未修改。'
fi
if [ -f "$module_file" ] && ! cmp -s "$module_file" "$source_lua"; then
    # Only upgrade the exact original module shipped by this project.
    module_hash=$(shasum -a 256 "$module_file" | awk '{print $1}')
    [ "$module_hash" = 'e1e3a6ec19d10fec820964caea9ff98663adc1d15a970f1808c58654a102bf0a' ] || fail_message 'Error: Existing golden-window.lua is customized or unrecognized. Check, back up, and move it aside manually; original files have not been modified.' '错误：已有 golden-window.lua 与随附版本不同，请先检查并备份后手动移开；原文件未修改。'
fi
loader='goldenWindow = require("golden-window")'
loader_count=$(grep -Fxc "$loader" "$cleaned" || true)
if [ "$loader_count" = 1 ]; then
    cp "$cleaned" "$scratch_dir/new-init.lua"
else
    cp "$scratch_dir/unrelated.lua" "$scratch_dir/new-init.lua"
    printf '\n%s\n' "$loader" >> "$scratch_dir/new-init.lua"
fi

printf '%s\n' "$language" > "$scratch_dir/new-language"
init_changed=1
module_changed=1
language_changed=1
if [ -f "$language_file" ] && cmp -s "$language_file" "$scratch_dir/new-language"; then language_changed=0; fi
if [ -f "$init_file" ] && cmp -s "$init_file" "$scratch_dir/new-init.lua"; then init_changed=0; fi
if [ -f "$module_file" ] && cmp -s "$module_file" "$source_lua"; then module_changed=0; fi
if [ "$init_changed" = 1 ] || [ "$module_changed" = 1 ] || [ "$language_changed" = 1 ]; then
    mkdir -p "$config_dir/backups"
    backup_dir=$(mktemp -d "$config_dir/backups/golden-window-$(date +%Y%m%d-%H%M%S).XXXXXX")
    if [ -f "$init_file" ]; then cp -p "$init_file" "$backup_dir/init.lua"; fi
    if [ -f "$module_file" ]; then cp -p "$module_file" "$backup_dir/golden-window.lua"; fi
    if [ -f "$language_file" ]; then cp -p "$language_file" "$backup_dir/.golden-window-language"; fi
    message 'Existing configuration backup: %s' '原有配置备份：%s' "$backup_dir"
    # Stage in the destination directory so each replacement is atomic.
    if [ "$module_changed" = 1 ]; then
        staged_module=$(mktemp "$config_dir/.golden-window.lua.XXXXXX")
        cp "$source_lua" "$staged_module"
        mv "$staged_module" "$module_file"
    fi
    if [ "$init_changed" = 1 ]; then
        staged_init=$(mktemp "$config_dir/.init.lua.XXXXXX")
        cp -p "$scratch_dir/new-init.lua" "$staged_init"
        mv "$staged_init" "$init_file"
    fi
    if [ "$language_changed" = 1 ]; then
        staged_language=$(mktemp "$config_dir/.golden-window-language.XXXXXX")
        cp "$scratch_dir/new-language" "$staged_language"
        mv "$staged_language" "$language_file"
    fi
else
    message 'Configuration is up to date; no files need rewriting.' '配置已是最新，无需改写。'
fi

if pgrep -x Hammerspoon >/dev/null 2>&1; then
    hs_cmd=$(command -v hs || true)
    if [ -z "$hs_cmd" ]; then
        for candidate in /opt/homebrew/bin/hs /usr/local/bin/hs "$app_path/Contents/Frameworks/hs/hs"; do
            if [ -x "$candidate" ]; then hs_cmd="$candidate"; break; fi
        done
    fi
    reload_ok=0
    if [ -n "$hs_cmd" ] && "$hs_cmd" -c 'print("golden-window IPC ready")' > "$scratch_dir/ipc.log" 2>&1; then
        # Reload invalidates the CLI port; confirm success through a new connection.
        "$hs_cmd" -c 'hs.reload()' > "$scratch_dir/reload.log" 2>&1 || true
        for attempt in 1 2 3; do
            if "$hs_cmd" -c "assert(goldenWindow and goldenWindow.menu); assert(goldenWindow.menu:title() == \"1.618:1\"); assert(goldenWindow.language == \"$language\"); print(\"golden-window loaded\")" > "$scratch_dir/check.log" 2>&1; then
                reload_ok=1
                break
            fi
            sleep 1
        done
    fi
    if [ "$reload_ok" = 1 ]; then
        message 'Hammerspoon configuration reloaded; the menu bar shows 1.618:1.' 'Hammerspoon 配置已重载，菜单栏显示 1.618:1。'
    else
        message 'Configuration saved. Click Reload Config in the Hammerspoon menu and check Console; automatic reload could not be confirmed.' '配置已写入。请从 Hammerspoon 菜单点击 Reload Config，并检查 Console；未确认自动重载成功。'
    fi
else
    if open "$app_path"; then
        message 'Hammerspoon started. Confirm that the menu bar shows 1.618:1 and Console has no loading errors.' '已启动 Hammerspoon。请确认菜单栏显示 1.618:1，Console 中无加载错误。'
    else
        message 'Configuration saved; open Hammerspoon manually.' '配置已写入，请手动打开 Hammerspoon。'
    fi
fi
message 'Usage: click 1.618:1 in the menu bar → 1.618:1 · Maximize and center.' '使用：点击菜单栏 1.618:1 → 1.618:1 · 最大尺寸并居中。'
message 'Before first use, enable Hammerspoon in System Settings → Privacy & Security → Accessibility; add %s if missing.' '首次使用需在“系统设置 → 隐私与安全性 → 辅助功能”中开启 Hammerspoon；缺失时添加 %s。' "$app_path"
message 'Installation does not move or resize windows.' '安装不会调整窗口。'
