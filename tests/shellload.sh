#!/bin/bash
# Loads the real shell the way a launch does, and fails on any QML error. Nothing else headless does
# this: an assignment to a property that no longer exists is a load error for the WHOLE shell, so
# Flea opens no window at all, and 0.1.4 reached a benchmark in that state with qmllint reporting 0
# regressions, tests/run-all.sh green across 22 suites, and cargo clean of warnings.
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

if ! command -v qs >/dev/null; then
    echo "shellload.sh: qs is not installed, cannot load the shell"
    exit 1
fi

log=$(mktemp) || exit 1
trap 'rm -f "$log"' EXIT INT TERM

# Offscreen and with no compositor, so this needs neither the display nor the display lock. A shell
# does not exit on its own, so the timeout expiring is the success path and 124 is not a failure.
# Seconds: generous enough for a cold QML compile on a loaded box, short enough for the battery.
load_seconds=25
env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout "$load_seconds" qs -p "$PWD/ui" >"$log" 2>&1
status=$?

# Sample input, one Quickshell log line: '  INFO: Configuration Loaded'
if grep -q 'Configuration Loaded' "$log"; then
    ok "the shell loads: qs reported Configuration Loaded"
else
    bad "qs never reported Configuration Loaded, so the shell did not load (timeout exit $status)"
fi

# Sample input, the 0.1.4 failure: 'ERROR:   caused by @ConvertDialog.qml[126:21]: Cannot assign to
# non-existent property "onHoverEntered"'. Colour codes sit before the level, so match it anywhere.
errors=$(grep -aciE 'ERROR|Failed to load configuration|unavailable|Cannot assign to non-existent' "$log")
if [ "$errors" -eq 0 ]; then
    ok "no QML error, no unavailable type, no assignment to a property that does not exist"
else
    bad "the shell logged $errors error line(s):"
    grep -aiE 'ERROR|unavailable|Cannot assign to non-existent' "$log" | head -5 | sed 's/^/     /'
fi

printf 'shellload: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
