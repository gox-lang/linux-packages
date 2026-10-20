#!/usr/bin/env bash
set -euo pipefail
# Invoked as an unprivileged user in a disposable container.
cd "$HOME"
gox version | grep -F "GOX Server v${1:?}"
if gox update > update.log 2>&1; then
    echo 'Package-managed update unexpectedly succeeded' >&2
    exit 1
fi
grep -Fq 'APT or DNF' update.log
gox createproject smoke-project
cd smoke-project
gox run --host 127.0.0.1 --port 3187 > "$HOME/gox-run.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
for attempt in $(seq 1 180); do
    if curl -fsS http://127.0.0.1:3187/ > "$HOME/page.html"; then
        grep -qi 'hello.*gox' "$HOME/page.html"
        exit 0
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
        cat "$HOME/gox-run.log"
        exit 1
    fi
    sleep 5
done
cat "$HOME/gox-run.log"
exit 1
