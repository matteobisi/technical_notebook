# Ghostty Terminal Configuration

## Overview
Ghostty is a fast, native, GPU-accelerated terminal emulator. This runbook covers the complete configuration for macOS including transparency, colors, and keybindings.

## Installation
```bash
brew install ghostty
```

## Nerd Font Requirement
For Starship prompt and icon support, install a Nerd Font:
```bash
brew tap homebrew/cask-fonts
brew install font-hack-nerd-font
```

## Configuration File Location
`~/.config/ghostty/config`

## Complete Configuration

```conf
# Ghostty Configuration
# Reload with: Cmd+Shift+Comma
# Transparency (90% opaque = 10% transparent)
background-opacity = 0.9
# ==========================
# FONT SETTINGS
# ==========================
# Using the same font from your Tabby config
font-family = MesloLGS NF
font-size = 16

# Font features for better rendering
font-thicken = false

# ==========================
# THEME & COLORS
# ==========================
theme = Duckbones
# ==========================
# WINDOW SETTINGS
# ==========================
window-padding-x = 8
window-padding-y = 8
window-padding-balance = true
window-padding-color = background

# macOS specific
macos-titlebar-style = tabs
macos-option-as-alt = false
window-decoration = true

# ==========================
# BEHAVIOR
# ==========================
# Scrollback
scrollback-limit = 10000

# Mouse
mouse-hide-while-typing = true
copy-on-select = false

# Shell integration (recommended)
shell-integration = detect
shell-integration-features = cursor,sudo,title

# Command to run (default shell)
command = /bin/zsh --login

# Split panes
#keybind = super+d=new_split:down
#keybind = super+shift+d=new_split:right

# Allow Ctrl+J to pass through (for Copilot CLI new line)
keybind = ctrl+j=text:\x0a

# ==========================
# CLIPBOARD
# ==========================
clipboard-read = allow
clipboard-write = allow
clipboard-trim-trailing-spaces = true

# ==========================
# MISC
# ==========================
# Confirm before closing with running processes
confirm-close-surface = true

# Cursor settings
cursor-style = block
cursor-style-blink = true

# Window theme
window-theme = auto
```

## Themes

To preview available themes:
```bash
ghostty +list-themes
```

The current configuration uses the `Duckbones` theme. You can change it by modifying the `theme` setting in the config file.

## Default Keybindings

### Window Management
- `Cmd+N` - New window
- `Cmd+T` - New tab
- `Cmd+W` - Close tab/window
- `Cmd+Shift+[` - Previous tab
- `Cmd+Shift+]` - Next tab
- `Cmd+1-9` - Switch to tab 1-9

### Panes/Splits
- `Cmd+D` - Split horizontally
- `Cmd+Shift+D` - Split vertically
- `Cmd+Option+Arrow` - Navigate between splits
- `Cmd+Shift+Arrow` - Resize splits

### Text Management
- `Cmd+C` - Copy
- `Cmd+V` - Paste
- `Cmd+F` - Find
- `Cmd+K` - Clear screen
- `Ctrl+J` - Newline (configured for Copilot CLI)

### View
- `Cmd++` - Increase font size
- `Cmd+-` - Decrease font size
- `Cmd+0` - Reset font size
- `Cmd+Shift+F` - Toggle fullscreen

### Config
- `Cmd+,` - Open config file
- `Cmd+Shift+R` - Reload configuration

## Troubleshooting

### Special Characters Not Working
If @ symbol or other special characters don't work, ensure `macos-option-as-alt` is **not** set to `true` in the config.

### Ctrl+J Not Working
Add explicit keybinding:
```conf
keybind = ctrl+j=text:\x0a
```

### Colors Not Showing
1. Ensure shell integration is enabled: `shell-integration = detect`
2. Add color configuration to your shell rc file (`.zshrc` or `.bashrc`)
3. Restart terminal or source the config: `source ~/.zshrc`

## References
- [Ghostty Documentation](https://ghostty.org)
- [Ghostty Config Reference](https://ghostty.org/docs/config)
