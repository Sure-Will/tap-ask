#!/usr/bin/env bash
# Deterministic parser/ownership/error tests; never inspect real processes or touch real samples.
set -euo pipefail
cd "$(dirname "$0")/.."
fixture="$(mktemp -d "${TMPDIR:-/tmp}/tapask-memory-tests.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/app/scripts"
cp scripts/measure-memory.sh "$fixture/app/scripts/measure-memory.sh"
export PATH="$fixture/bin:$PATH"
export MEMORY_FIXTURE_ROOT="$fixture"
export MEMORY_FIXTURE_MODE=normal

cat > "$fixture/bin/pgrep" <<'SH'
#!/usr/bin/env bash
case "$MEMORY_FIXTURE_MODE" in
    missing) exit 1 ;;
    multiple) printf '100\n101\n' ;;
    *) echo 100 ;;
esac
SH
cat > "$fixture/bin/ps" <<'SH'
#!/usr/bin/env bash
if [[ "$2" == 100 ]]; then
    if [[ "$MEMORY_FIXTURE_MODE" == restarted && -f "$MEMORY_FIXTURE_ROOT/sampled" ]]; then
        echo 'Fri Nov  6 02:00:00 2026'
    else
        echo 'Fri Nov  6 01:00:00 2026'
    fi
    exit 0
fi
case "$2" in
    200) echo '/System/Library/Frameworks/WebKit.framework/com.apple.WebKit.WebContent' ;;
    201) echo '/System/Library/Frameworks/WebKit.framework/com.apple.WebKit.Networking' ;;
    202)
        [[ -f "$MEMORY_FIXTURE_ROOT/gpu-exited" ]] && exit 1
        echo '/System/Library/Frameworks/WebKit.framework/com.apple.WebKit.GPU'
        ;;
    203) exit 1 ;;
    204) echo /usr/bin/unrelated-process ;;
    *) echo "Unexpected ps lookup: $*" >&2; exit 2 ;;
esac
SH
cat > "$fixture/bin/log" <<'SH'
#!/usr/bin/env bash
[[ "$MEMORY_FIXTURE_MODE" == log-failed ]] && exit 1
[[ "$*" == *'processID == 100 AND eventMessage CONTAINS "didConnectToProcess"'* ]] || exit 2
[[ "$*" == *'--start 2026-11-06 01:00:00'* ]] || exit 2
[[ "$MEMORY_FIXTURE_MODE" == no-webkit ]] && exit 0
printf '%s\n' \
    'WebProcessProxy::didConnectToProcess [PID=200]' \
    'NetworkProcessProxy::didConnectToProcess [PID=201]' \
    'GPUProcessProxy::didConnectToProcess [PID=202]' \
    'WebProcessProxy::didConnectToProcess [PID=200]' \
    'WebProcessProxy::didConnectToProcess [PID=203]' \
    'WebProcessProxy::didConnectToProcess [PID=204]'
SH
cat > "$fixture/bin/footprint" <<'SH'
#!/usr/bin/env bash
[[ "$1 $2 $3" == '-f bytes --noCategories' ]] || exit 2
printf '%s\n' "$4" >> "$MEMORY_FIXTURE_ROOT/sampled"
if [[ "$MEMORY_FIXTURE_MODE" == footprint-failed && "$4" == 202 ]]; then
    echo 'Permission denied' >&2
    exit 1
fi
if [[ "$MEMORY_FIXTURE_MODE" == gpu-exits && "$4" == 202 ]]; then
    touch "$MEMORY_FIXTURE_ROOT/gpu-exited"
    exit 1
fi
case "$4" in
    100) bytes=1048576 ;;
    200) bytes=2097152 ;;
    201) bytes=3145728 ;;
    202) bytes=4194304 ;;
    *) echo 'Measured a stale or unrelated PID' >&2; exit 2 ;;
esac
echo 'Footprint: 99999999 B (16384 bytes per page)'
echo 'Auxiliary data:'
echo '    phys_footprint_peak: 99999999 B'
[[ "$MEMORY_FIXTURE_MODE" == malformed ]] && exit 0
echo "    phys_footprint: $bytes B"
SH
chmod +x "$fixture/bin/pgrep" "$fixture/bin/ps" "$fixture/bin/log" "$fixture/bin/footprint"
measurement="$fixture/app/scripts/measure-memory.sh"
csv="$fixture/app/build/memory.csv"

"$measurement" TapAsk-Debug 'round,"1"' > "$fixture/output"
[[ "$(cat "$fixture/sampled")" == $'100\n200\n201\n202' ]]
[[ "$(head -n 1 "$csv")" == 'timestamp,label,total_mib,process_count' ]]
[[ "$(tail -n 1 "$csv")" == *',"round,""1""",10.000,4' ]]

for mode in missing multiple log-failed footprint-failed malformed restarted; do
    export MEMORY_FIXTURE_MODE="$mode"
    cp "$csv" "$fixture/before.csv"
    rm -f "$fixture/sampled"
    if "$measurement" TapAsk-Debug > "$fixture/output" 2>&1; then
        echo "FAIL: $mode unexpectedly succeeded" >&2
        exit 1
    fi
    cmp "$csv" "$fixture/before.csv"
done

export MEMORY_FIXTURE_MODE=gpu-exits
"$measurement" TapAsk-Debug > "$fixture/output"
[[ "$(tail -n 1 "$csv")" == *',"TapAsk-Debug",6.000,3' ]]
export MEMORY_FIXTURE_MODE=no-webkit
"$measurement" TapAsk-Debug > "$fixture/output" 2>&1
[[ "$(tail -n 1 "$csv")" == *',"TapAsk-Debug",1.000,1' ]]
[[ "$(wc -l < "$csv" | tr -d ' ')" == 4 ]]
echo 'Memory script fixtures passed (ownership, deduplication, byte totals, CSV, exits and error paths).'
