# Kitty Terminal Cheatsheet

Kitty is a fast, feature-rich, GPU-based terminal emulator. This cheatsheet provides a quick reference for configuration and common key bindings.

## Configuration

Kitty's configuration is controlled by a single file: `~/.config/kitty/kitty.conf`. You can create this file if it doesn't exist and add the following configurations to customize your terminal.

### Common Customizations

Here are some of the most common settings you might want to tweak after your initial setup.

#### Font

You can change the font family and size to your preference.

```conf
# Font family
font_family      FiraCode Nerd Font
bold_font        auto
italic_font      auto
bold_italic_font auto

# Font size
font_size 14.0
```

#### Themes and Colors

Kitty comes with a variety of built-in themes. You can also define your own colors.

To use a built-in theme, you can include it in your configuration. A list of available themes can be found in the official documentation.

```conf
# Include a theme
include themes/gruvbox_dark.conf
```

You can also set the colors manually:

```conf
# Foreground and background colors
foreground #d8d8d8
background #181818

# Cursor colors
cursor           #c0c0c0
cursor_text_color #181818

# Selection colors
selection_foreground #181818
selection_background #f0f0f0
```

#### Cursor Customization

You can customize the cursor's shape, color, and blink interval.

```conf
# Cursor shape (block, beam, underline)
cursor_shape     block

# Stop blinking after a certain time (in seconds)
cursor_blink_interval 0.5
cursor_stop_blinking_after 15.0
```

#### Shell Integration

Kitty's shell integration enables features like jumping between prompts, viewing command output in a pager, and more.

To enable it, add the following to your `kitty.conf`:

```conf
shell_integration enabled
```

And add the following to your shell's startup file (e.g., `.bashrc`, `.zshrc`):

```sh
# For zsh
autoload -U compinit && compinit
# For bash
source <(kitty +complete setup bash)
# For fish
kitty +complete setup fish | source
```

---

## Key Bindings

Kitty uses `ctrl+shift` for many of its default bindings on Linux, and `cmd` on macOS. The `kitty_mod` key is `ctrl+shift` on Linux and `cmd` on macOS.

### Tabs

- **New Tab**: `kitty_mod+t`
- **Close Tab**: `kitty_mod+q`
- **Next Tab**: `kitty_mod+right` or `kitty_mod+]`
- **Previous Tab**: `kitty_mod+left` or `kitty_mod+[`
- **Go to Tab 1-10**: `kitty_mod+1` to `kitty_mod+0`
- **Set Tab Title**: `kitty_mod+alt+t`

### Windows

- **New Window**: `kitty_mod+enter`
- **Close Window**: `kitty_mod+w`
- **Next Window**: `kitty_mod+}`
- **Previous Window**: `kitty_mod+}`

### Navigation

- **Scroll Up**: `kitty_mod+up` or `kitty_mod+k`
- **Scroll Down**: `kitty_mod+down` or `kitty_mod+j`
- **Scroll to Top**: `kitty_mod+home`
- **Scroll to Bottom**: `kitty_mod+end`

### Miscellaneous

- **Copy to Clipboard**: `kitty_mod+c`
- **Paste from Clipboard**: `kitty_mod+v`
- **Open a new kitty window**: `kitty_mod+n`
- **Toggle fullscreen**: `kitty_mod+f11`
- **Increase font size**: `kitty_mod+equal`
- **Decrease font size**: `kitty_mod+minus`
- **Reset font size**: `kitty_mod+backspace`
- **Open a URL**: `kitty_mod+e`
