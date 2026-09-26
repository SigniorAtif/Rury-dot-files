# SigniorAtif

A personal Quickshell desktop for Hyprland: bar, dock, overview, lock screen,
notification centre and wallpaper-driven Material You theming.

## Install

Arch Linux only.

```sh
git clone https://github.com/<you>/dotfiles ~/dotfiles
cd ~/dotfiles
./install.sh
```

It installs the packages, builds the Python environment, fetches the font,
then links the config into `~/.config`. Anything it would overwrite is moved
into a timestamped backup directory first — it never deletes.

```
./install.sh --no-packages    # just the dotfiles
./install.sh --with-latex     # also build MicroTeX, for LaTeX rendering
./install.sh --help
```

Then log out and back in, or `hyprctl reload && qs -c rury`.

## Layout

| Path | What |
|---|---|
| `.config/quickshell/rury/` | the shell itself — run with `qs -c rury` |
| `.config/rury/` | live settings the shell reads and writes |
| `.config/hypr/` | Hyprland config, in Lua |
| `.config/matugen/` | colour templates for GTK, Qt, hyprlock, fuzzel, kitty |

`~/.config` links into this repository, so changes made in the settings app
show up here as ordinary git changes.

## Origin and license

This is a modified version of [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)
("illogical-impulse"), forked at commit `2f0c8bf` (2026-09-14). Copyright for
the original work remains with end-4 and the upstream contributors.

**This fork is not kept in sync with upstream.** It has diverged and will keep
diverging; do not expect parity, and report problems here rather than there.

Modifications by Atif Ahmed, 2026: the shell was renamed to `rury` internally
and SigniorAtif in its interface; the background, lock and parallax animations
were reworked; keybinds and window rules were ported from a previous Fedora
setup; the installer was rewritten to depend on packages directly.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the [GNU General Public License](LICENSE) for details.

### Third-party components

- `.config/quickshell/rury/modules/common/widgets/shapes/` — Apache License 2.0
- `.config/quickshell/rury/modules/common/functions/fuzzysort.js` — MIT, Copyright (c) 2018 Stephen Kamenar
- Google Sans Flex — SIL Open Font License 1.1
- `requirements.txt` — the Python dependency list from upstream
- `illogical-impulse-quickshell-git` — end-4's build of [Quickshell](https://git.outfoxxed.me/quickshell/quickshell) by outfoxxed, pinned to the API this shell targets
