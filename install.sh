#!/usr/bin/env bash
# Installs the SigniorAtif desktop: packages, Python environment, fonts, dotfiles.
# Arch Linux only. Run as your normal user; it asks for sudo when it needs it.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP="$HOME/.config/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
VENV="$HOME/.local/state/quickshell/.venv"

DO_PACKAGES=1
DO_VENV=1
DO_FONTS=1
DO_LINK=1
LINK=0
WITH_LATEX=0

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

  --no-packages   skip pacman/AUR installation
  --no-venv       skip the Python environment
  --no-fonts      skip font installation
  --no-dotfiles   skip putting the dotfiles into ~/.config
  --link          symlink ~/.config into this repository instead of copying,
                  for working on the dotfiles (the clone must then stay put)
  --with-latex    also build MicroTeX, for LaTeX rendering in the shell
  -h, --help      show this message

The dotfiles are copied, so the clone can be deleted afterwards. Anything
they would overwrite in ~/.config is moved into a timestamped backup
directory first; nothing is deleted.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --no-packages) DO_PACKAGES=0 ;;
        --no-venv)     DO_VENV=0 ;;
        --no-fonts)    DO_FONTS=0 ;;
        --no-dotfiles|--no-link) DO_LINK=0 ;;
        --link)        LINK=1 ;;
        --with-latex)  WITH_LATEX=1 ;;
        -h|--help)     usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

say()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m warning:\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31m error:\033[0m %s\n' "$1" >&2; exit 1; }

[ -f /etc/arch-release ] || die "this installer only supports Arch Linux"
[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root"
command -v pacman >/dev/null || die "pacman not found"

# --- packages --------------------------------------------------------------
# These are the dependency lists of end-4's illogical-impulse-* meta packages,
# written out directly so this repo does not depend on someone else's empty
# packages to carry a list.

PKGS_REPO=(
    # base tooling
    bc coreutils cliphist cmake curl wget ripgrep jq xdg-user-dirs rsync go-yq
    # audio
    cava pavucontrol-qt wireplumber pipewire-pulse libdbusmenu-gtk3 playerctl
    # started in service mode by hypr/hyprland/execs.lua
    easyeffects
    # backlight and sensors
    geoclue brightnessctl ddcutil upower
    # hyprland and wayland
    hyprland hyprsunset hypridle hyprlock hyprpicker wl-clipboard
    # portals
    xdg-desktop-portal xdg-desktop-portal-kde xdg-desktop-portal-gtk
    xdg-desktop-portal-hyprland
    # kde integration
    bluedevil gnome-keyring networkmanager plasma-nm polkit-kde-agent
    dolphin systemsettings breeze
    # screen capture
    hyprshot slurp swappy tesseract tesseract-data-eng wf-recorder
    # widgets and utilities
    fuzzel glib2 imagemagick songrec translate-shell libqalculate
    wtype ydotool
    # usb automount, started by hypr/custom/execs.lua
    udiskie
    # theming and shell
    eza fish fontconfig kitty matugen starship
    ttf-jetbrains-mono-nerd
    # python build environment
    clang uv gtk4 libadwaita libsoup3 libportal-gtk4 gobject-introspection
    # Qt modules the shell's QML imports (quickshell itself is installed below)
    qt6-5compat qt6-imageformats qt6-multimedia qt6-positioning
    qt6-quicktimeline qt6-sensors qt6-svg qt6-tools qt6-translations
    qt6-virtualkeyboard qt6-wayland kirigami kdialog syntax-highlighting
)

PKGS_AUR=(
    adw-gtk-theme-git breeze-plus darkly-bin
    otf-space-grotesk ttf-material-symbols-variable-git
    ttf-readex-pro ttf-rubik-vf ttf-twemoji
    wlogout
    bibata-cursor-theme-bin
    # AVIF wallpapers
    qt6-avif-image-plugin
)

ensure_aur_helper() {
    if command -v yay >/dev/null; then AUR=yay; return; fi
    if command -v paru >/dev/null; then AUR=paru; return; fi

    say "Installing yay (no AUR helper found)"
    sudo pacman -S --needed --noconfirm git base-devel
    local tmp
    tmp="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
    AUR=yay
}

if [ "$DO_PACKAGES" -eq 1 ]; then
    say "Installing repository packages"
    sudo pacman -S --needed --noconfirm "${PKGS_REPO[@]}"

    # Quickshell 0.3.2 from extra, the release the shell is written against.
    # Skipped when another build already provides it: end-4's
    # illogical-impulse-quickshell-git conflicts with it, and --noconfirm
    # would refuse the swap.
    if ! pacman -T quickshell >/dev/null; then
        sudo pacman -S --needed --noconfirm quickshell
    fi

    ensure_aur_helper
    say "Installing AUR packages with $AUR"
    "$AUR" -S --needed --noconfirm "${PKGS_AUR[@]}"

    if [ "$WITH_LATEX" -eq 1 ]; then
        say "Installing MicroTeX for LaTeX rendering"
        sudo pacman -S --needed --noconfirm tinyxml2 gtkmm3 gtksourceviewmm cairomm
        "$AUR" -S --needed --noconfirm illogical-impulse-microtex-git
    fi
fi

# --- python environment ----------------------------------------------------
if [ "$DO_VENV" -eq 1 ]; then
    say "Building the Python environment at $VENV"
    command -v uv >/dev/null || die "uv is required for the Python environment"
    mkdir -p "$(dirname "$VENV")"
    uv venv --clear --python 3.12 "$VENV"
    uv pip install --python "$VENV/bin/python" -r "$REPO/requirements.txt"
fi

# --- fonts -----------------------------------------------------------------
if [ "$DO_FONTS" -eq 1 ]; then
    say "Installing Google Sans Flex"
    dest="$HOME/.local/share/fonts/rury-google-sans-flex"
    if [ -d "$dest" ]; then
        echo "  already present, skipping"
    else
        tmp="$(mktemp -d)"
        # OFL-licensed; Google publishes it only through their API, so this
        # mirror is the practical source.
        git clone --depth 1 https://github.com/end-4/google-sans-flex "$tmp/gsf"
        mkdir -p "$dest"
        cp -a "$tmp/gsf/"* "$dest/"
        rm -rf "$tmp"
    fi
    fc-cache -f >/dev/null

    say "Installing the shell icon"
    mkdir -p "$HOME/.local/share/icons"
    cp "$REPO/.config/quickshell/rury/assets/icons/Rury.png" \
       "$HOME/.local/share/icons/rury.png"
    command -v gtk-update-icon-cache >/dev/null &&
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons" 2>/dev/null || true
fi

# --- dotfiles --------------------------------------------------------------
# Puts one file or directory from the repository in place under ~/.config:
# a copy by default, a symlink with --link.
place_one() {
    local src="$1" dst="$2"

    # Already in place.
    if [ "$LINK" -eq 1 ]; then
        if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
            echo "  ok       $dst"
            return
        fi
    elif [ ! -L "$dst" ] && [ -e "$dst" ] && diff -rq "$src" "$dst" >/dev/null 2>&1; then
        echo "  ok       $dst"
        return
    fi

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mkdir -p "$BACKUP/$(dirname "${dst#"$HOME"/}")"
        mv "$dst" "$BACKUP/${dst#"$HOME"/}"
        echo "  backed up $dst"
    fi

    mkdir -p "$(dirname "$dst")"
    if [ "$LINK" -eq 1 ]; then
        ln -s "$src" "$dst"
        echo "  linked   $dst"
    else
        cp -a "$src" "$dst"
        echo "  copied   $dst"
    fi
}

# A copy replaces a directory wholesale, so files the desktop writes into it
# at runtime (saved settings, wallpaper colours) are carried over from the
# backup the copy just made.
keep_from_backup() {
    local rel="$1"

    [ "$LINK" -eq 0 ] && [ -f "$BACKUP/$rel" ] || return 0
    cp "$BACKUP/$rel" "$HOME/$rel"
    echo "  kept     $HOME/$rel"
}

# For files an app rewrites itself: copy once, then leave the app's copy alone.
copy_if_absent() {
    local src="$1" dst="$2"

    if [ -e "$dst" ]; then
        echo "  kept     $dst"
        return
    fi

    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "  copied   $dst"
}

if [ "$DO_LINK" -eq 1 ]; then
    if [ "$LINK" -eq 1 ]; then
        say "Linking dotfiles into ~/.config"
    else
        say "Copying dotfiles into ~/.config"
    fi
    place_one "$REPO/.config/hypr"            "$HOME/.config/hypr"
    place_one "$REPO/.config/quickshell/rury" "$HOME/.config/quickshell/rury"
    place_one "$REPO/.config/rury"            "$HOME/.config/rury"
    place_one "$REPO/.config/matugen"         "$HOME/.config/matugen"
    keep_from_backup .config/rury/config.json
    keep_from_backup .config/hypr/hyprland/colors.lua
    keep_from_backup .config/hypr/hyprlock/colors.conf

    # Terminal: kitty runs fish, and fish starts the starship prompt. Only
    # config.fish is placed, since fish writes fish_variables next to it.
    place_one "$REPO/.config/kitty"            "$HOME/.config/kitty"
    place_one "$REPO/.config/fish/config.fish" "$HOME/.config/fish/config.fish"
    place_one "$REPO/.config/starship.toml"    "$HOME/.config/starship.toml"

    # Desktop pieces Hyprland and the keybinds call on. fuzzel_theme.ini is
    # matugen output, so only fuzzel.ini is placed.
    place_one "$REPO/.config/xdg-desktop-portal"   "$HOME/.config/xdg-desktop-portal"
    place_one "$REPO/.config/fontconfig/fonts.conf" "$HOME/.config/fontconfig/fonts.conf"
    place_one "$REPO/.config/fuzzel/fuzzel.ini"    "$HOME/.config/fuzzel/fuzzel.ini"
    place_one "$REPO/.config/wlogout"              "$HOME/.config/wlogout"

    # Qt apps follow kdeglobals (QT_QPA_PLATFORMTHEME=kde). The colours in it
    # are rewritten by kde-material-you-colors on every wallpaper change, so
    # only the style, icon and font keys are set here.
    place_one "$REPO/.config/kde-material-you-colors" "$HOME/.config/kde-material-you-colors"
    copy_if_absent "$REPO/.config/darklyrc"  "$HOME/.config/darklyrc"
    copy_if_absent "$REPO/.config/dolphinrc" "$HOME/.config/dolphinrc"
    if command -v kwriteconfig6 >/dev/null; then
        kg() { kwriteconfig6 --file kdeglobals --group "$1" --key "$2" "$3"; }
        kg KDE     widgetStyle          Darkly
        kg Icons   Theme                breeze-plus-dark
        kg General TerminalApplication  "kitty -1"
        kg General font                 "Google Sans Flex,11,-1,5,500,0,0,0,0,0,0,0,0,0,0,1,Medium"
        kg General menuFont             "Google Sans Flex,10,-1,5,500,0,0,0,0,0,0,0,0,0,0,1,Medium"
        kg General toolBarFont          "Google Sans Flex,10,-1,5,500,0,0,0,0,0,0,0,0,0,0,1,Medium"
        kg General smallestReadableFont "Google Sans Flex,9,-1,5,500,0,0,0,0,0,0,0,0,0,0,1,Medium"
        kg General fixed                "JetBrainsMono Nerd Font,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
        echo "  set      $HOME/.config/kdeglobals style, icons and fonts"
    else
        echo "  skipped  kdeglobals: kwriteconfig6 not found"
    fi

    [ -d "$BACKUP" ] && echo "  replaced files are in $BACKUP"
fi

say "Done"
cat <<EOF

Log out and back into Hyprland, or from a running session:

    hyprctl reload
    qs -c rury

EOF
if [ "$LINK" -eq 1 ]; then
    cat <<EOF
~/.config links into this repository, so changes you make in the settings
app show up as ordinary git changes here. Keep the clone where it is.
EOF
else
    cat <<EOF
The dotfiles were copied into ~/.config, so this clone is no longer needed.
To update later, clone or pull again and run ./install.sh --no-packages
--no-venv; your shell settings and wallpaper colours are kept.
EOF
fi
