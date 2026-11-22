---
name: rury-shell
description: Control Atif's desktop shell (Quickshell "rury" on Hyprland): media, brightness, wallpaper, theme, sidebars, and read window/workspace state.
---

# The rury shell

Atif's desktop: Hyprland (Lua config in ~/.config/hypr, symlinked from ~/dotfiles) and the Quickshell config
`rury` (~/.config/quickshell/rury). Visible name: SigniorAtif.

## Read state (safe, no approval)
- `hyprctl -j clients` windows; `hyprctl -j workspaces`; `hyprctl -j activewindow`; `hyprctl -j monitors`.
- `playerctl metadata --format '{{artist}} - {{title}}'`, `wpctl get-volume @DEFAULT_AUDIO_SINK@`.

## Shell commands (`qs -c rury ipc call <target> <function> [args]`)
- Media: `mpris playPause | next | previous | pauseAll`
- Brightness: `brightness increment | decrement`
- Wallpaper: `wallpapers apply /path/to/image` (also recolours the theme)
- Theme: `theme toggleLightDark`
- Panels: `sidebarLeft toggle|open|close`, `sidebarRight toggle`, `overlay toggle`, `cheatsheet toggle`
- List everything: `qs -c rury ipc show`

## Volume
`wpctl set-volume @DEFAULT_AUDIO_SINK@ 40%` / `wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle`.

## Don't
- Don't edit files under ~/dotfiles or ~/.config/quickshell/rury unless Atif asks: the live shell reloads on save,
  and a broken file breaks his desktop (and his lock screen if it is locked).
- `hyprctl dispatch ...` changes his session (focus, workspaces): it asks for approval; only do it when asked.
