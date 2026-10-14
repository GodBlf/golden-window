# golden-window

English | [简体中文](README.zh-CN.md)

Install or reuse Hammerspoon and configure the largest centered **1.618:1 golden-ratio windows** with one script. For macOS; no Python required. Run from a zsh or Bash terminal.

## Background

Make Mac windows consistent golden rectangles for a pleasing desktop, including when using Stage Manager. Just for fun—it is about how the windows look.

## Installation

Copy the project to your Mac, then run:

```bash
bash ~/Projects/golden-window/install.sh
```

At startup, enter `1` for English or `2` for Simplified Chinese. Press Enter to accept the default: English on first use, then the language selected during the last successful installation. Installer messages and the Hammerspoon UI use the same language. Run the installer again to switch. External tools such as Homebrew keep their own output language.

Without interactive input, the installer uses the saved language or English. Set the language explicitly to skip the prompt:

```bash
GOLDEN_WINDOW_LANG=en bash install.sh
GOLDEN_WINDOW_LANG=zh-CN bash install.sh
```

Only `en` and `zh-CN` are accepted; other values cause an error. The choice is saved in `.golden-window-language` in the configuration directory. The module defaults to English if that file cannot be read or its contents are invalid.

If Hammerspoon is already installed, downloading is skipped. Otherwise, the script runs `brew install --cask hammerspoon`. If Homebrew is missing, install it using the instructions on the [Homebrew website](https://brew.sh/) before running the script again.

Before first use, enable Hammerspoon in **System Settings → Privacy & Security → Accessibility**. If it is missing, add `/Applications/Hammerspoon.app` (or its actual location in your user Applications folder). Quit and reopen Hammerspoon if permission has not taken effect.

Click **1.618:1** in the menu bar, then **1.618:1 · Maximize and center**. With Chinese selected, the item is **1.618:1 · 最大尺寸并居中**. Installation does not move or resize windows. There are no keyboard shortcuts or restore action.

## Behavior and configuration

Each ordinary visible window uses its own display's work area, excluding the menu bar and Dock. The largest golden rectangle is calculated with `width = min(available width, available height × 1.618)` and centered. The ratio includes the title bar; integer rounding can cause small differences. Windows may overlap. Full-screen and nonstandard windows are skipped; windows in other Spaces and minimized windows are not handled. Application size constraints may prevent some windows from reaching the target. The menu action reports the result.

The installer deploys `~/.hammerspoon/golden-window.lua` and adds this loader to `init.lua` once:

```lua
goldenWindow = require("golden-window")
```

Existing files are backed up under `~/.hammerspoon/backups/` before changes. Reinstalling does not duplicate the loader. Other settings and shortcuts are preserved. Only the exact verified legacy inline implementation is migrated automatically; ambiguous conflicts stop installation for manual review. The known original module is identified by its SHA-256 hash and backed up before automatic upgrade. Customized or unrecognized modules stop installation. The language file is backed up too, and symbolic-link configuration files are not overwritten.

If a running Hammerspoon has working `hs` IPC, the script reloads the configuration and verifies the menu title and language. Otherwise, click **Reload Config** in the Hammerspoon menu. There is no need to enable IPC for this project. A new installation starts Hammerspoon. If you have configured a different Hammerspoon configuration directory, use `GOLDEN_WINDOW_CONFIG_DIR=/actual/directory bash install.sh`; the script does not change Hammerspoon's configuration directory for you.

## Adding other ratios

Only 1.618:1 is currently provided. To add another ratio, add an entry to `menuItems` in the project's `golden-window.lua`:

```lua
{title = text.extraRatio, fn = function() applyLayout(16 / 9, "16:9") end},
```

Add `extraRatio = "16:9 · Maximize and center"` to `translations.en` and `extraRatio = "16:9 · 最大尺寸并居中"` to `translations["zh-CN"]`.

Also update the `selectedRatio` validation to accept both `1.618:1` and `16:9`. The existing `selectRatio(label)` updates the menu bar title and saves the last selection. Back up the project or deployed module before editing. The installer refuses to overwrite customized modules: review and move the old module aside before reinstalling.
