#!/usr/bin/env bash
# Random wallpaper from a Moebooru site.
#   --site konachan|yandere   which booru to pull from (default: konachan)
#   --nsfw                    pull rating:questionable/explicit instead of rating:safe
#
# Note on Konachan: konachan.net only serves rating:safe, so NSFW has to come from
# konachan.com, which sits behind a Cloudflare bot challenge. Drop a cookie header
# into ~/.config/rury/konachan_cookie.txt (a cf_clearance you copied
# out of your own browser, plus the matching user agent in the config's
# networking.userAgent) and konachan.com works. Without it we fall back to yande.re.

get_pictures_dir() {
    if command -v xdg-user-dir &> /dev/null; then
        xdg-user-dir PICTURES
        return
    fi

    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
    if [ -f "$config_file" ]; then
        local pictures_path
        pictures_path=$(source "$config_file" >/dev/null 2>&1; echo "$XDG_PICTURES_DIR")
        echo "${pictures_path/#\$HOME/$HOME}"
        return
    fi

    echo "$HOME/Pictures"
}

QUICKSHELL_CONFIG_NAME="rury"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
PICTURES_DIR=$(get_pictures_dir)
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ruryConfigPath="$HOME/.config/rury/config.json"
konachanCookiePath="$HOME/.config/rury/konachan_cookie.txt"

site="konachan"
nsfw=0
while [ $# -gt 0 ]; do
    case "$1" in
        --site) site="$2"; shift 2 ;;
        --nsfw) nsfw=1; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

mkdir -p "$PICTURES_DIR/Wallpapers"
userAgent=$(jq -r '.networking.userAgent // empty' "$ruryConfigPath" 2>/dev/null)

# Tag pools. Every tag below was checked against the site's own tag database, so none
# of them are dead weight. One is picked per attempt to keep runs from looking alike.
konachanSfwTags=(
    "landscape" "scenic" "sky" "clouds" "stars" "night" "city" "sunset" "water"
    "flowers" "forest" "snow" "rain" "moon" "tree" "building" "autumn" "nobody"
)
# Counts are konachan's own (cum 9.6k, nipples 48k, pussy 28k, uncensored 18k, ...).
konachanNsfwTags=(
    "cum" "nipples" "pussy" "uncensored" "nude" "sex" "breasts" "no_bra" "ass"
    "spread_legs" "censored" "pussy_juice" "anus" "topless" "nopan" "cameltoe"
    "wet" "erect_nipples" "condom" "masturbation" "panty_pull" "naked_shirt"
    "paizuri" "fellatio" "lactation"
)
yandereNsfwTags=(
    "cum" "nipples" "breasts" "pussy" "uncensored" "nude" "naked" "sex" "topless"
    "bottomless" "no_bra" "erect_nipples" "paizuri" "fellatio" "masturbation"
    "pussy_juice" "spread_pussy" "anus" "cameltoe" "undressing" "breast_grab"
    "nipple_slip" "bukkake" "wet"
)

# Sites to try, in order. Konachan NSFW keeps yande.re as a fallback so the button
# still produces something when the Cloudflare cookie is missing or stale.
if [ "$site" = "yandere" ]; then
    apis=("https://yande.re/post.json")
    tagPools=("yandereNsfwTags")
elif [ "$nsfw" = 1 ]; then
    apis=("https://konachan.com/post.json" "https://yande.re/post.json")
    tagPools=("konachanNsfwTags" "yandereNsfwTags")
else
    apis=("https://konachan.net/post.json")
    tagPools=("konachanSfwTags")
fi

if [ "$nsfw" = 1 ]; then
    ratingTag="-rating%3Asafe"
else
    ratingTag="rating%3Asafe"
fi
# Moebooru caps anonymous queries at ~6 tags, so it stays at one theme tag + filters.
baseTags="$ratingTag+width%3A%3E%3D1920"

link=""
usedSite=""
for i in "${!apis[@]}"; do
    api="${apis[$i]}"
    poolName="${tagPools[$i]}"
    eval "pool=(\"\${${poolName}[@]}\")"

    cookieArgs=()
    if [[ "$api" == *konachan.com* ]] && [ -f "$konachanCookiePath" ]; then
        cookieArgs=(-b "$(tr -d '\n' < "$konachanCookiePath")")
    fi

    failures=0
    for attempt in 1 2 3 4; do
        # Narrow the page range on each retry so thinner tags still land on a post.
        case $attempt in
            1|2) page=$((1 + RANDOM % 30)) ;;
            3) page=$((1 + RANDOM % 8)) ;;
            4) page=1 ;;
        esac
        tag=${pool[$((RANDOM % ${#pool[@]}))]}
        response=$(curl -sfL -A "$userAgent" "${cookieArgs[@]}" "$api?tags=$tag+$baseTags&limit=1&page=$page")
        if [ -z "$response" ]; then
            failures=$((failures + 1))
            # Two dead requests in a row means the host is blocking us (Cloudflare),
            # not just rate limiting: move on instead of sitting in retries.
            [ "$failures" -ge 2 ] && break
            sleep 1
            continue
        fi
        failures=0
        candidate=$(echo "$response" | jq -r 'if type == "array" and length > 0 then .[0].file_url else empty end' 2>/dev/null)
        if [ -n "$candidate" ]; then
            link="$candidate"
            usedSite=$(echo "$api" | awk -F/ '{print $3}')
            echo "Picked $tag from $usedSite (page $page)"
            break
        fi
    done
    [ -n "$link" ] && break
done

if [ -z "$link" ]; then
    echo "Failed to fetch a wallpaper" >&2
    [ "$nsfw" = 1 ] && [ ! -f "$konachanCookiePath" ] && \
        echo "Tip: konachan.com needs a cf_clearance cookie in $konachanCookiePath" >&2
    exit 1
fi

# Unique filename per download: the old fixed random_wallpaper.ext got overwritten by
# the next roll, which meant losing an image before you had a chance to save it.
ext=$(echo "$link" | awk -F. '{print $NF}' | tr -dc 'A-Za-z0-9')
[ -z "$ext" ] && ext="jpg"
[ "$nsfw" = 1 ] && kind="nsfw" || kind="sfw"
siteSlug=$(echo "$usedSite" | tr -d '.')
downloadPath="$PICTURES_DIR/Wallpapers/${siteSlug}_${kind}_$(date +%Y%m%d_%H%M%S).$ext"

# The image hosts want a Referer from the site they belong to, and they drop the odd
# connection outright, so retry generously.
if ! curl -sfL --retry 5 --retry-delay 2 --retry-all-errors --connect-timeout 15 \
    -A "$userAgent" -H "Referer: https://$usedSite/" "${cookieArgs[@]}" \
    "$link" -o "$downloadPath"; then
    echo "Failed to download $link" >&2
    rm -f "$downloadPath"
    exit 1
fi

"$SCRIPT_DIR/../switchwall.sh" --image "$downloadPath"
