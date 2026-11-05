#!/usr/bin/env bash
# Lists a wallpaper collection for the gallery (Super+Shift+H): one JSON array, newest
# first, of {path, mtime, tags}. Tags come from <collection>/.meta/<md5>.json where a
# save left one, keyed by md5 so a renamed file keeps its tags. Only the top level is
# listed, which is where the settings page's Save to button puts wallpapers.
#
#   collection_index.sh <collection dir>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/saved_wallpapers.sh"

dir="${1%/}"
[ -d "$dir" ] || { echo '[]'; exit 0; }
loadSavedWallpapers "$dir"

declare -A md5ForPath=()
for md5 in "${!savedWallpaperMd5s[@]}"; do
    md5ForPath["${savedWallpaperMd5s[$md5]}"]="$md5"
done

while IFS=$'\t' read -r mtime path; do
    printf '%s\t%s\t%s\n' "${md5ForPath["$path"]}" "${mtime%.*}" "$path"
done < <(find "$dir" -maxdepth 1 -type f -iregex '.*\.\(jpe?g\|png\|webp\|avif\|bmp\|gif\)' -printf '%T@\t%p\n') \
| jq -R -n -c --slurpfile meta <(cat "$dir"/.meta/*.json 2>/dev/null) '
    ($meta | map(select(.md5) | {key: .md5, value: (.tags // "")}) | from_entries) as $tags
    | [inputs | split("\t") | {path: .[2], mtime: (.[1] | tonumber), tags: ($tags[.[0]] // "")}]
    | sort_by(-.mtime)'
