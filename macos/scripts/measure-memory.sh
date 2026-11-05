#!/usr/bin/env bash
# Read-only process inspection; only build/memory.csv is written.
# Usage: scripts/measure-memory.sh TapAsk-Debug [label]
# Sum per-process phys_footprint ledgers, not RSS or a shared-region-deduplicated total.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

if [[ $# -lt 1 || $# -gt 2 || -z "$1" ]]; then
    echo "Usage: $0 <process-name> [label]" >&2
    exit 64
fi
process_name="$1"
label="${2:-$process_name}"
if [[ "$label" == *$'\n'* || "$label" == *$'\r'* ]]; then
    echo "Label must fit on one CSV line" >&2
    exit 64
fi

# Escape pgrep's regular expression so the argument is an exact process name.
pattern="$(printf '%s' "$process_name" | sed 's/[][\.^$*+?(){}|\\]/\\&/g')"
if ! matches="$(pgrep -x "$pattern")"; then
    echo "Cannot find process '$process_name' (or process inspection is unavailable)" >&2
    exit 1
fi
if [[ "$matches" == *$'\n'* ]]; then
    echo "Multiple '$process_name' processes found; keep one instance running before measuring: $matches" >&2
    exit 1
fi
app_pid="$matches"
app_start="$(ps -p "$app_pid" -o lstart=)"
app_start="${app_start#"${app_start%%[![:space:]]*}"}"
start_time="$(date -j -f '%a %b %e %T %Y' "$app_start" '+%Y-%m-%d %H:%M:%S')"

# WebKit XPC processes are children of launchd. Only this app's connection records
# since this launch establish ownership; never sweep all system WebKit processes.
connections="$(log show --start "$start_time" --style compact --info --debug \
    --predicate "processID == $app_pid AND eventMessage CONTAINS \"didConnectToProcess\"")"
candidate_pids="$(printf '%s\n' "$connections" | awk '
    { while (match($0, /\[PID=[0-9]+\]/)) {
        print substr($0, RSTART + 5, RLENGTH - 6)
        $0 = substr($0, RSTART + RLENGTH)
    } }
' | sort -nu)"
pids=("$app_pid")
names=("$process_name")
while IFS= read -r pid; do
    [[ -n "$pid" && "$pid" != "$app_pid" ]] || continue
    if ! command_name="$(ps -p "$pid" -o comm=)" || [[ -z "$command_name" ]]; then
        continue # Exited since its connection was logged.
    fi
    case "${command_name##*/}" in
        com.apple.WebKit.WebContent*|com.apple.WebKit.Networking*|com.apple.WebKit.GPU*)
            pids+=("$pid")
            names+=("${command_name##*/}")
            ;;
    esac
done <<< "$candidate_pids"
if [[ ${#pids[@]} -eq 1 ]]; then
    echo "No live WebKit processes found in this app's connection log; this sample covers the app only." >&2
fi

total_bytes=0
process_count=0
printf '%-8s %-40s %20s\n' PID PROCESS 'phys_footprint (bytes)'
for index in "${!pids[@]}"; do
    pid="${pids[$index]}"
    if ! sample="$(footprint -f bytes --noCategories "$pid" 2>&1)"; then
        if [[ "$pid" != "$app_pid" ]] && ! ps -p "$pid" -o pid= >/dev/null; then
            continue # A WebKit process can exit during sampling.
        fi
        printf '%s\n' "$sample" >&2
        echo "Unable to measure PID $pid; no CSV row appended." >&2
        exit 1
    fi
    bytes="$(printf '%s\n' "$sample" | awk '
        /^[[:space:]]*phys_footprint[[:space:]]*:/ {
            sub(/^[^:]*:[[:space:]]*/, "")
            if ($1 ~ /^[0-9]+$/) print $1
        }
    ')"
    if [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "$sample" >&2
        echo "Missing or ambiguous phys_footprint for PID $pid; no CSV row appended." >&2
        exit 1
    fi
    printf '%-8s %-40s %20s\n' "$pid" "${names[$index]}" "$bytes"
    total_bytes=$((total_bytes + bytes))
    process_count=$((process_count + 1))
done

# Do not record a partial run after the app exits/restarts during a sample.
if [[ "$(ps -p "$app_pid" -o lstart=)" != *"$app_start" ]]; then
    echo "Target app exited or changed during sampling; no CSV row appended." >&2
    exit 1
fi
total_mib="$(awk -v bytes="$total_bytes" 'BEGIN { printf "%.3f", bytes / 1048576 }')"
printf 'total_phys_footprint=%s bytes total_mib=%s processes=%s label=%s\n' \
    "$total_bytes" "$total_mib" "$process_count" "$label"
mkdir -p build
if [[ ! -s build/memory.csv ]]; then
    printf 'timestamp,label,total_mib,process_count\n' >> build/memory.csv
fi
csv_label="${label//\"/\"\"}"
printf '%s,"%s",%s,%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$csv_label" \
    "$total_mib" "$process_count" >> build/memory.csv
