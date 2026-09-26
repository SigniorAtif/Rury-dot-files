#!/bin/bash

INTERVAL=2
TOTAL_DURATION=30
SOURCE_TYPE="auto"  # monitor | input | auto | both
WORKDIR=$(mktemp -d /tmp/songrec_XXXXXX)

while getopts "i:t:s:" opt; do
  case $opt in
    i) INTERVAL=$OPTARG ;;
    t) TOTAL_DURATION=$OPTARG ;;
    s) SOURCE_TYPE=$OPTARG ;;
    *) exit 1 ;;
  esac
done

if ! command -v songrec >/dev/null 2>&1; then
    rmdir "$WORKDIR" 2>/dev/null
    exit 1
fi

monitor_device() {
    local sink
    sink=$(pactl get-default-sink 2>/dev/null) || return 1
    [ -n "$sink" ] && echo "${sink}.monitor"
}

input_device() {
    pactl info 2>/dev/null | awk -F': ' '/^Default Source:/ {print $2}'
}

# True when something is actually playing to the default sink, so that
# "auto" can fall back to the microphone when the desktop is silent.
system_audio_playing() {
    pactl list sink-inputs 2>/dev/null | grep -q "Corked: no"
}

device_exists() {
    [ -n "$1" ] && pactl list short sources 2>/dev/null | awk '{print $2}' | grep -qx "$1"
}

DEVICES=()
case "$SOURCE_TYPE" in
    monitor)
        DEVICES=("$(monitor_device)")
        ;;
    input)
        DEVICES=("$(input_device)")
        ;;
    auto)
        if system_audio_playing; then
            DEVICES=("$(monitor_device)")
        else
            DEVICES=("$(input_device)")
        fi
        ;;
    both)
        DEVICES=("$(monitor_device)" "$(input_device)")
        ;;
    *)
        echo "Invalid source type" >&2
        rmdir "$WORKDIR" 2>/dev/null
        exit 1
        ;;
esac

# Drop devices that don't exist; bail out only if nothing usable is left.
USABLE=()
for dev in "${DEVICES[@]}"; do
    device_exists "$dev" && USABLE+=("$dev")
done
if [ ${#USABLE[@]} -eq 0 ]; then
    rmdir "$WORKDIR" 2>/dev/null
    exit 1
fi

PIDS=()
cleanup() {
    # Each listener runs in its own session, so killing the group takes
    # songrec down with the subshell that spawned it.
    for pid in "${PIDS[@]}"; do
        kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

# One listener per device. Each writes its first match to its own result
# file, so two listeners can never interleave into one JSON line.
index=0
for dev in "${USABLE[@]}"; do
    result="$WORKDIR/result.$index"
    setsid bash -c '
        songrec listen --audio-device "$1" --request-interval "$2" --json --disable-mpris 2>/dev/null |
        while IFS= read -r line; do
            if echo "$line" | grep -q "\"matches\"[[:space:]]*:"; then
                printf "%s\n" "$line" > "$3"
                break
            fi
        done
    ' _ "$dev" "$INTERVAL" "$result" &
    PIDS+=($!)
    index=$((index + 1))
done

# Poll for whichever listener matches first, up to the total duration.
deadline=$((SECONDS + TOTAL_DURATION))
while [ $SECONDS -lt $deadline ]; do
    for result in "$WORKDIR"/result.*; do
        if [ -s "$result" ]; then
            cat "$result"
            exit 0
        fi
    done
    # Every listener died (e.g. device disappeared): nothing left to wait for.
    alive=0
    for pid in "${PIDS[@]}"; do
        kill -0 "$pid" 2>/dev/null && alive=1
    done
    [ $alive -eq 0 ] && break
    sleep 0.5
done

exit 0
