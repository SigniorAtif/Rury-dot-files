# Sourced by the random wallpaper scripts so a fetch can pass over images that are
# already in the collection the settings page's "Save to" button would put them in.
# Boorus publish each file's md5, and save_wallpaper.sh copies byte for byte, so the
# API's md5 is enough to tell before anything is downloaded.
# Expects PICTURES_DIR to be set by the script sourcing this.

# Mirrors Directories.booruDownloadsNsfw / Directories.classworkWallpapers, the two
# destinations the settings page hands save_wallpaper.sh.
savedWallpaperDir() {
    if [ "$1" = "nsfw" ]; then
        echo "$PICTURES_DIR/homework/🌶️"
    else
        echo "$HOME/git-clones/walls/Classwork"
    fi
}

# md5 -> the saved file that has it
declare -A savedWallpaperMd5s=()

# Hashing the collections every run would mean reading half a gigabyte each, so md5s
# are cached per directory and only redone for files whose size or mtime changed.
loadSavedWallpapers() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    local cacheDir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/saved_wallpapers"
    local cacheFile="$cacheDir/$(echo -n "$dir" | md5sum | cut -d' ' -f1).tsv"
    mkdir -p "$cacheDir"

    local -A cached=()
    local size mtime path md5
    if [ -f "$cacheFile" ]; then
        while IFS=$'\t' read -r size mtime path md5; do
            cached["$size $mtime $path"]="$md5"
        done < "$cacheFile"
    fi

    local fresh=""
    while IFS=$'\t' read -r size mtime path; do
        md5="${cached["$size $mtime $path"]}"
        [ -z "$md5" ] && md5=$(md5sum "$path" | cut -d' ' -f1)
        [ -n "$md5" ] || continue
        savedWallpaperMd5s["$md5"]="$path"
        fresh+="$size"$'\t'"$mtime"$'\t'"$path"$'\t'"$md5"$'\n'
    done < <(find "$dir" -maxdepth 1 -type f -printf '%s\t%T@\t%p\n')
    printf '%s' "$fresh" > "$cacheFile"
}

isSavedWallpaper() {
    [ -n "$1" ] && [ -n "${savedWallpaperMd5s["$1"]}" ]
}
