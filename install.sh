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
WITH_LATEX=0

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

  --no-packages   skip pacman/AUR installation
  --no-venv       skip the Python environment
  --no-fonts      skip font installation
  --no-link       skip linking the dotfiles into ~/.config
  --with-latex    also build MicroTeX, for LaTeX rendering in the shell
  -h, --help      show this message

Anything it would overwrite in ~/.config is moved into a timestamped
backup directory first; nothing is deleted.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --no-packages) DO_PACKAGES=0 ;;
        --no-venv)     DO_VENV=0 ;;
        --no-fonts)    DO_FONTS=0 ;;
        --no-link)     DO_LINK=0 ;;
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
    # theming and shell
    eza fish fontconfig kitty matugen starship
    ttf-jetbrains-mono-nerd
    # python build environment
    clang uv gtk4 libadwaita libsoup3 libportal-gtk4 gobject-introspection
)

PKGS_AUR=(
    adw-gtk-theme-git breeze-plus darkly-bin
    otf-space-grotesk ttf-material-symbols-variable-git
    ttf-readex-pro ttf-rubik-vf ttf-twemoji
    wlogout
    bibata-cursor-theme-bin
    # Quickshell itself. This is end-4's build, pinned to 0.1.0; the shell is
    # written against that API, so AUR's newer quickshell-git will not work.
    illogical-impulse-quickshell-git
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
    uv venv --python 3.12 "$VENV"
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
    cp "$REPO/.config/quickshell/rury/assets/icons/rury.png" \
       "$HOME/.local/share/icons/rury.png"
    command -v gtk-update-icon-cache >/dev/null &&
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons" 2>/dev/null || true
fi

# --- dotfiles --------------------------------------------------------------
link_one() {
    local src="$1" dst="$2"

    # Already pointing where it should.
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        echo "  ok       $dst"
        return
    fi

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mkdir -p "$BACKUP/$(dirname "${dst#"$HOME"/}")"
        mv "$dst" "$BACKUP/${dst#"$HOME"/}"
        echo "  backed up $dst"
    fi

    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    echo "  linked   $dst"
}

if [ "$DO_LINK" -eq 1 ]; then
    say "Linking dotfiles into ~/.config"
    link_one "$REPO/.config/hypr"            "$HOME/.config/hypr"
    link_one "$REPO/.config/quickshell/rury" "$HOME/.config/quickshell/rury"
    link_one "$REPO/.config/rury"            "$HOME/.config/rury"
    link_one "$REPO/.config/matugen"         "$HOME/.config/matugen"

    [ -d "$BACKUP" ] && echo "  replaced files are in $BACKUP"
fi

say "Done"
cat <<EOF

Log out and back into Hyprland, or from a running session:

    hyprctl reload
    qs -c rury

The shell reads its settings from ~/.config/rury/config.json, which is a
link into this repository, so changes you make in the settings app show up
as ordinary git changes here.
EOF
