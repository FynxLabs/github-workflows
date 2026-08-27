#!/usr/bin/env bash
# Generic compat test entrypoint for Tenebrux Zig projects.
# Reads test commands from environment variables:
#   TEST_COMMANDS      - newline-separated commands to run headless
#   X11_TEST_COMMANDS  - newline-separated commands to run under Xvfb + Openbox
set -euo pipefail

DISPLAY_NUM=:99
export DISPLAY=$DISPLAY_NUM

XVFB_PID=""
OPENBOX_PID=""

cleanup() {
    [ -n "$OPENBOX_PID" ] && kill "$OPENBOX_PID" 2>/dev/null || true
    [ -n "$XVFB_PID" ] && kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> zig version: $(zig version)"
echo "==> distro: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
echo ""

# ── Headless test commands ────────────────────────────────────────────────────
if [ -n "${TEST_COMMANDS:-}" ]; then
    while IFS= read -r cmd; do
        cmd="$(echo "$cmd" | xargs)"
        [ -z "$cmd" ] && continue
        echo "==> $cmd"
        eval "$cmd"
        echo ""
    done <<< "$TEST_COMMANDS"
else
    echo "==> No TEST_COMMANDS specified, skipping headless tests"
    echo ""
fi

# ── X11 test commands (under Xvfb + Openbox) ─────────────────────────────────
if [ -n "${X11_TEST_COMMANDS:-}" ]; then
    echo "==> Starting Xvfb on $DISPLAY_NUM..."
    Xvfb $DISPLAY_NUM -screen 0 1920x1080x24 &
    XVFB_PID=$!

    for i in $(seq 1 20); do
        if xprop -display $DISPLAY_NUM -root > /dev/null 2>&1; then
            echo "    Xvfb ready (${i}s)"
            break
        fi
        if [ "$i" -eq 20 ]; then
            echo "    ERROR: Xvfb did not start in time"
            exit 1
        fi
        sleep 0.5
    done

    echo "==> Starting Openbox WM..."
    openbox &
    OPENBOX_PID=$!
    sleep 1

    if ! xprop -display $DISPLAY_NUM -root _NET_SUPPORTED > /dev/null 2>&1; then
        echo "    WARNING: _NET_SUPPORTED not set - Openbox may not have started cleanly"
    fi

    # Set a primary output so RandR tests see primary_count >= 1.
    # Use cut instead of awk for OpenMandriva compatibility.
    PRIMARY=$(xrandr --query 2>/dev/null | grep " connected" | head -1 | cut -d' ' -f1)
    echo "    Primary output candidate: '${PRIMARY}'"
    if [ -n "$PRIMARY" ]; then
        xrandr --output "$PRIMARY" --primary 2>/dev/null && \
            echo "    Primary set: $PRIMARY" || \
            echo "    WARNING: xrandr --primary failed for $PRIMARY"
    else
        echo "    WARNING: No connected output found - primary not set"
    fi

    echo ""
    while IFS= read -r cmd; do
        cmd="$(echo "$cmd" | xargs)"
        [ -z "$cmd" ] && continue
        echo "==> $cmd"
        eval "$cmd"
        echo ""
    done <<< "$X11_TEST_COMMANDS"
fi

echo "==> All tests passed."
