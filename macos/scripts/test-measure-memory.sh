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
if [[ "$MEMORY_FIXTURE_MODE" == all-webkit-exit && -f "$MEMORY_FIXTURE_ROOT/sampled" ]]; then
    exit 1
fi
if [[ "$4" == lstart= ]]; then
    case "$2" in
        200)
            case "$MEMORY_FIXTURE_MODE" in
                reused-pid|only-reused) echo 'Fri Nov  6 01:00:08 2026' ;;
                connection-grace) echo 'Fri Nov  6 01:00:07 2026' ;;
                *) echo 'Fri Nov  6 01:00:04 2026' ;;
            esac
            ;;
        201) echo 'Fri Nov  6 01:00:02 2026' ;;
        202) echo 'Fri Nov  6 00:59:59 2026' ;;
        *) echo "Unexpected process start lookup: $*" >&2; exit 2 ;;
    esac
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
if [[ "$MEMORY_FIXTURE_MODE" == only-exited ]]; then
    echo '2026-11-06 01:00:06.000 Df TapAsk-Debug[100] WebProcessProxy::didConnectToProcess [PID=203]'
    exit 0
fi
if [[ "$MEMORY_FIXTURE_MODE" == only-reused ]]; then
    echo '2026-11-06 01:00:05.500 Df TapAsk-Debug[100] WebProcessProxy::didConnectToProcess [PID=200]'
    exit 0
fi
printf '%s\n' \
    '2026-11-06 01:00:01.000 Df TapAsk-Debug[100] WebProcessProxy::didConnectToProcess [PID=200]' \
    '2026-11-06 01:00:02.000 Df TapAsk-Debug[100] NetworkProcessProxy::didConnectToProcess [PID=201]' \
    '2026-11-06 01:00:03.000 Df TapAsk-Debug[100] GPUProcessProxy::didConnectToProcess [PID=202]' \
    '2026-11-06 01:00:05.500 Df TapAsk-Debug[100] WebProcessProxy::didConnectToProcess [PID=200]' \
    '2026-11-06 01:00:06.000 Df TapAsk-Debug[100] WebProcessProxy::didConnectToProcess [PID=203]' \
    '2026-11-06 01:00:07.000 Df TapAsk-Debug[100] WebProcessProxy::didConnectToProcess [PID=204]'
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
if [[ "$MEMORY_FIXTURE_MODE" == all-webkit-exit && "$4" != 100 ]]; then
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

# The latest connection, not the first one, establishes the current PID's ownership.
# A process starting exactly two seconds after that connection is still accepted.
export MEMORY_FIXTURE_MODE=connection-grace
rm -f "$fixture/sampled"
"$measurement" TapAsk-Debug > "$fixture/output"
[[ "$(cat "$fixture/sampled")" == $'100\n200\n201\n202' ]]
[[ "$(tail -n 1 "$csv")" == *',"TapAsk-Debug",10.000,4' ]]

export MEMORY_FIXTURE_MODE=reused-pid
rm -f "$fixture/sampled"
"$measurement" TapAsk-Debug > "$fixture/output" 2> "$fixture/stderr"
if [[ "$(cat "$fixture/sampled")" != $'100\n201\n202' ]]; then
    echo 'FAIL: reused WebKit PID 200 was measured' >&2
    exit 1
fi
[[ "$(tail -n 1 "$csv")" == *',"TapAsk-Debug",8.000,3' ]]
[[ "$(cat "$fixture/stderr")" == *'Skipping PID 200:'*'PID reused'* ]]

for mode in missing multiple log-failed footprint-failed malformed restarted no-webkit only-exited only-reused all-webkit-exit; do
    export MEMORY_FIXTURE_MODE="$mode"
    cp "$csv" "$fixture/before.csv"
    rm -f "$fixture/sampled"
    if "$measurement" TapAsk-Debug > "$fixture/output" 2>&1; then
        echo "FAIL: $mode unexpectedly succeeded" >&2
        exit 1
    fi
    cmp "$csv" "$fixture/before.csv"
    case "$mode" in
        no-webkit|only-exited|only-reused)
            [[ ! -f "$fixture/sampled" ]]
            [[ "$(cat "$fixture/output")" == *'No live owned WebKit processes'*'no CSV row appended'* ]]
            ;;
        all-webkit-exit)
            [[ "$(cat "$fixture/sampled")" == $'100\n200\n201\n202' ]]
            [[ "$(cat "$fixture/output")" == *'No WebKit processes were measured'*'no CSV row appended'* ]]
            ;;
    esac
done

export MEMORY_FIXTURE_MODE=gpu-exits
"$measurement" TapAsk-Debug > "$fixture/output"
[[ "$(tail -n 1 "$csv")" == *',"TapAsk-Debug",6.000,3' ]]
[[ "$(wc -l < "$csv" | tr -d ' ')" == 5 ]]
echo 'Memory script fixtures passed (ownership, PID reuse, connection grace, deduplication, byte totals, CSV, incomplete-sample rejection, exits and error paths).'
