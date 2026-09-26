#!/usr/bin/env bash
# Fetch a GitHub user's avatar into the cache, replacing it only when it
# actually changed. Prints one word: changed, unchanged, or offline.
#
# The shell draws the cached file, so it always has something to show; this
# only decides whether a new picture is worth a crossfade.

set -euo pipefail

user="${1:-}"
size="${2:-128}"

if [ -z "$user" ]; then
    echo "usage: github-avatar.sh <github-user> [size]" >&2
    exit 2
fi

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/user"
dest="$cache_dir/github-avatar.png"
mkdir -p "$cache_dir"

tmp="$(mktemp "$cache_dir/.github-avatar.XXXXXX")"
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT

# A failure here is not an error: being offline just means we keep the cache.
if ! curl -fsSL --max-time 15 "https://github.com/${user}.png?size=${size}" -o "$tmp" 2>/dev/null; then
    echo offline
    exit 0
fi

# GitHub serves an HTML error page for unknown users, so check it is an image.
if [ ! -s "$tmp" ] || ! file --mime-type -b "$tmp" | grep -q '^image/'; then
    echo offline
    exit 0
fi

if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    echo unchanged
    exit 0
fi

mv -f "$tmp" "$dest"
trap - EXIT
echo changed
