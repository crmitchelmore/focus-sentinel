#!/bin/zsh
# Local developer run loop. Refuse to stop another checkout's running app.
set -eu

MODE="${1:-run}"
case "$MODE" in
    run|--debug|--logs|--telemetry|--verify) ;;
    --help)
        print 'usage: script/build_and_run.sh [--debug|--logs|--telemetry|--verify]'
        exit 0 ;;
    *) print -u2 "Unknown mode: $MODE"; exit 2 ;;
esac

ROOT="${0:A:h:h}"
DD="${FOCUS_DERIVED_DATA:-$ROOT/DerivedData/Run}"
DD="${DD:A}"
APP="$DD/Build/Products/Debug/FocusSentinel.app"
BINARY="$APP/Contents/MacOS/FocusSentinel"
LOG_DIR="${FOCUS_LOG_DIR:-$ROOT/build/run-logs}"
mkdir -p "$LOG_DIR"

# A shared bundle identifier does not establish ownership. Only stop this
# entrypoint's exact executable; leave any other agent's app running.
app_pids=(${(f)"$(pgrep -x FocusSentinel || true)"})
for app_pid in $app_pids; do
    executable=$(ps -p "$app_pid" -o comm=)
    if [[ "$executable" != "$BINARY" ]]; then
        print -u2 "Another Focus checkout is running (PID $app_pid): $executable"
        print -u2 'Coordinate with its owner before running this checkout.'
        exit 1
    fi
done
for app_pid in $app_pids; do
    if [[ "$(ps -p "$app_pid" -o comm= || true)" == "$BINARY" ]]; then
        kill -TERM "$app_pid"
    fi
done

cd "$ROOT"
print "Building Focus Sentinel. Log: $LOG_DIR/build.log"
if ! xcodebuild -project FocusSentinel.xcodeproj -scheme FocusSentinel \
    -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DD" FOCUS_GIT_HASH="$(git rev-parse --short HEAD)" \
    build > "$LOG_DIR/build.log" 2>&1; then
    tail -60 "$LOG_DIR/build.log"
    exit 1
fi

if [[ "$MODE" == --debug ]]; then
    exec lldb -- "$BINARY"
fi
/usr/bin/open -n "$APP"
case "$MODE" in
    --logs)
        exec /usr/bin/log stream --info --style compact \
            --predicate 'process == "FocusSentinel"' ;;
    --telemetry)
        exec /usr/bin/log stream --info --style compact \
            --predicate 'subsystem BEGINSWITH "com.chrismitchelmore.FocusSentinel"' ;;
    --verify)
        sleep 2
        for app_pid in $(pgrep -x FocusSentinel || true); do
            if [[ "$(ps -p "$app_pid" -o comm=)" == "$BINARY" ]]; then
                print "Running: $APP (PID $app_pid)"
                exit 0
            fi
        done
        print -u2 "Focus did not remain running: $APP"
        exit 1 ;;
esac
