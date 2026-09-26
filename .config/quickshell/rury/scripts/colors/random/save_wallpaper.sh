#!/usr/bin/env bash
# Copy the wallpaper that's currently set into a collection directory, renamed to the
# next free serial number so nothing already in there gets clobbered.
#   save_wallpaper.sh <destination-directory>

destDir="$1"
if [ -z "$destDir" ]; then
    echo "Usage: save_wallpaper.sh <destination-directory>" >&2
    exit 1
fi

ruryConfigPath="$HOME/.config/rury/config.json"
wallpaperPath=$(jq -r '.background.wallpaperPath // empty' "$ruryConfigPath" 2>/dev/null)
wallpaperPath="${wallpaperPath#file://}"

if [ -z "$wallpaperPath" ] || [ ! -f "$wallpaperPath" ]; then
    echo "No current wallpaper to save" >&2
    exit 1
fi

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
