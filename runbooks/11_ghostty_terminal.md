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
# Ghostty Terminal Configuration

# Transparency (90% opaque = 10% transparent)
background-opacity = 0.9

# Font configuration
font-family = "Hack Nerd Font Mono"
font-size = 15

# Theme - Nord-inspired colors for better file/folder visibility
# Background and foreground
background = #000000
foreground = #d8dee9

# Cursor
cursor-color = #d8dee9

# Selection
selection-background = #4c566a
selection-foreground = #d8dee9

# Normal colors
palette = 0=#3b4252
palette = 1=#bf616a
palette = 2=#a3be8c
palette = 3=#ebcb8b
palette = 4=#81a1c1
palette = 5=#b48ead
palette = 6=#88c0d0
palette = 7=#e5e9f0

# Bright colors
palette = 8=#4c566a
palette = 9=#bf616a
palette = 10=#a3be8c
palette = 11=#ebcb8b
palette = 12=#81a1c1
palette = 13=#b48ead
palette = 14=#8fbcbb
palette = 15=#eceff4

# Window settings
window-padding-x = 10
window-padding-y = 10

# Shell integration for better colors
shell-integration = detect

# macOS-specific settings
macos-titlebar-style = tabs

# Cursor settings
cursor-style = block
cursor-style-blink = true

# Copy/paste behavior
copy-on-select = true
clipboard-trim-trailing-spaces = true

# Mouse
mouse-hide-while-typing = true

# Window
window-save-state = always
confirm-close-surface = false

# Performance
unfocused-split-opacity = 0.8

# Keybinds - ensure Ctrl+J passes through for newlines
keybind = ctrl+j=text:\x0a
```

## Shell Configuration for Colors

Add to `~/.zshrc`:

```bash
# Enable colored output for ls
export CLICOLOR=1
export LSCOLORS=ExGxFxdaCxDaDahbadacec
alias ls='ls -G'
```

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
