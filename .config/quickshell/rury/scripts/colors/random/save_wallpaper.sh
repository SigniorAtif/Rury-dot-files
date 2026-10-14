#!/usr/bin/env bash
# Copy the wallpaper that's currently set into a collection directory, renamed to the
# next free serial number so nothing already in there gets clobbered.
#   save_wallpaper.sh [--check] <destination-directory> [<wallpaper>]
#   --check       only print the file it's already saved as (nothing if it isn't); the
#                 settings page uses this to label its save button
#   <wallpaper>   defaults to the one in the config; the settings page passes its own so
#                 it never races the config file being written

checkOnly=0
if [ "$1" = "--check" ]; then
    checkOnly=1
    shift
fi
destDir="$1"
if [ -z "$destDir" ]; then
    echo "Usage: save_wallpaper.sh [--check] <destination-directory> [<wallpaper>]" >&2
    exit 1
fi

wallpaperPath="$2"
if [ -z "$wallpaperPath" ]; then
    ruryConfigPath="$HOME/.config/rury/config.json"
    wallpaperPath=$(jq -r '.background.wallpaperPath // empty' "$ruryConfigPath" 2>/dev/null)
fi
wallpaperPath="${wallpaperPath#file://}"

if [ -z "$wallpaperPath" ] || [ ! -f "$wallpaperPath" ]; then
    [ "$checkOnly" = 1 ] && exit 0
    echo "No current wallpaper to save" >&2
    exit 1
fi

# A file with the same md5 already in there means it was saved before: don't add a copy.
source "$(dirname "${BASH_SOURCE[0]}")/saved_wallpapers.sh"
loadSavedWallpapers "$destDir"
wallpaperMd5=$(md5sum "$wallpaperPath" | cut -d' ' -f1)
if isSavedWallpaper "$wallpaperMd5"; then
    savedAs="${savedWallpaperMd5s["$wallpaperMd5"]}"
    [ "$checkOnly" = 1 ] && echo "$savedAs" || echo "Already saved as $savedAs"
    exit 0
fi
[ "$checkOnly" = 1 ] && exit 0

mkdir -p "$destDir" || exit 1

# Existing collections are numbered (41.png, 44.jpg, ...), so continue that sequence.
highest=0
shopt -s nullglob
for existing in "$destDir"/*; do
    name=$(basename "$existing")
    number="${name%%.*}"
    if [[ "$number" =~ ^[0-9]+$ ]] && [ "$number" -gt "$highest" ]; then
        highest="$number"
    fi
done
shopt -u nullglob

ext="${wallpaperPath##*.}"
serial=$((highest + 1))
# Guard against a race or an unnumbered duplicate: never overwrite an existing file.
while [ -e "$destDir/$serial.$ext" ]; do
    serial=$((serial + 1))
done
destPath="$destDir/$serial.$ext"

if cp -n "$wallpaperPath" "$destPath"; then
    echo "Saved to $destPath"
else
    echo "Failed to save to $destPath" >&2
    exit 1
fi
