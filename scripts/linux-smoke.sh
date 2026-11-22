#!/usr/bin/env bash
set -euo pipefail

for component in agent relay; do
    cargo test --locked --manifest-path "/source/$component/Cargo.toml"
    cargo build --locked --release --manifest-path "/source/$component/Cargo.toml" --bin "ai-notify-$component"
    cp "$CARGO_TARGET_DIR/release/ai-notify-$component" /output/
done

scratch=$(mktemp -d)
relay_pid=
trap 'if [ -n "$relay_pid" ]; then kill "$relay_pid" 2>/dev/null || true; fi' EXIT
export AINOTIFY_LISTEN=127.0.0.1:18787
export AINOTIFY_DB="$scratch/test.sqlite3"
export AINOTIFY_WRITERS='{"linux-ci":"local-ci-linux-writer-fixture-only-77"}'
export AINOTIFY_READER_TOKEN=local-ci-linux-reader-fixture-only-78
url=http://127.0.0.1:18787
state="$scratch/state"
hooks="$scratch/claude hooks"
agent=/output/ai-notify-agent

printf '%s' local-ci-linux-writer-fixture-only-77 |
    "$agent" --home "$state" configure --name 'Linux CI' --relay "$url" --include-message
"$agent" --home "$state" hooks install claude-code --tool-home "$hooks" --frontend-id claude-code-cli --frontend-label "Claude Code CLI"
command=$(sed -nE 's/^[[:space:]]*"command": "(.*)",?$/\1/p' "$hooks/settings.json")
test -n "$command"
printf '%s' '{"hook_event_name":"Stop","cwd":"/work/ci","session_id":"linux-session","last_assistant_message":"Linux 本轮完成"}' |
    sh -c "$command"
if "$agent" --home "$state" run --once; then
    printf '%s\n' 'Offline send unexpectedly passed' >&2
    exit 1
fi

/output/ai-notify-relay >/output/relay-linux.log 2>&1 &
relay_pid=$!
for attempt in $(seq 1 30); do
    if curl -fSs --noproxy '*' "$url/healthz" >/dev/null 2>&1; then break; fi
    sleep 0.2
done
"$agent" --home "$state" run --once
feed=$(curl -fSs --noproxy '*' -H "Authorization: Bearer $AINOTIFY_READER_TOKEN" "$url/v1/events")
printf '%s' "$feed" | grep -F 'Linux 本轮完成' >/dev/null
printf '%s' "$feed" | grep -F '"device_id":"linux-ci"' >/dev/null
printf '%s' "$feed" | grep -F '"frontend":{"id":"claude-code-cli","label":"Claude Code CLI"}' >/dev/null
printf '%s\n' 'PASS: Native Linux build, installed shell Hook, offline recovery and UTF-8 event' | tee /output/receipt.txt
