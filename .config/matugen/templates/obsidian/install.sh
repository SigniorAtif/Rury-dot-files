#!/usr/bin/env bash
# Copies the matugen-rendered SigniorAtif theme into every Obsidian vault
# listed in Obsidian's config. Run by matugen as the template's post_hook,
# so the theme follows each wallpaper change; Obsidian reloads it live.
#
# Each palettes/<name>.css also becomes a fixed-colour theme,
# "SigniorAtif <Name>": the rendered theme with that palette laid over it.

set -euo pipefail

THEME_NAME="SigniorAtif"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
RENDERED="$STATE_DIR/quickshell/user/generated/obsidian/theme.css"
SRC_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
MANIFEST="$SRC_DIR/manifest.json"
VAULTS_JSON="$CONFIG_DIR/obsidian/obsidian.json"

[[ -f "$RENDERED" && -f "$VAULTS_JSON" ]] || exit 0
command -v jq >/dev/null || exit 0

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# Build every theme once: <name>/manifest.json and <name>/theme.css
build_theme() { # name, css files...
    local name="$1"; shift
    mkdir -p "$BUILD/$name"
    jq --arg name "$name" '.name = $name' "$MANIFEST" > "$BUILD/$name/manifest.json"
    cat "$@" > "$BUILD/$name/theme.css"
}

build_theme "$THEME_NAME" "$RENDERED"
for palette in "$SRC_DIR"/palettes/*.css; do
    [[ -f "$palette" ]] || continue
    base="$(basename "$palette" .css)"
    build_theme "$THEME_NAME ${base^}" "$RENDERED" "$palette"
done

# Write only what changed, then rename, so Obsidian never reads a
# half-written file and does not reload a theme whose colours stayed put.
install_file() { # src, dest
    local tmp
    tmp="$(dirname "$2")/.$(basename "$2").tmp"
    cmp -s "$1" "$2" && return 0
    cp "$1" "$tmp"
    mv -f "$tmp" "$2"
}

jq -r '.vaults[].path' "$VAULTS_JSON" | while IFS= read -r vault; do
    # only vaults that exist and have been opened in Obsidian
    [[ -d "$vault/.obsidian" ]] || continue
    for theme in "$BUILD"/*/; do
        name="$(basename "$theme")"
        dest="$vault/.obsidian/themes/$name"
        mkdir -p "$dest"
        install_file "$theme/manifest.json" "$dest/manifest.json"
        install_file "$theme/theme.css" "$dest/theme.css"
    done
done
