#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache_dir="$(mktemp -d)"
lifecycle_home="$cache_dir/home"
lifecycle_state="$cache_dir/state"
lifecycle_browser_state="$cache_dir/browser-state"
lifecycle_attach_count="$cache_dir/attach-count"
lifecycle_token_file="$cache_dir/extension-token"
lifecycle_cli="$cache_dir/playwright-cli"

cleanup() {
  HOME="$lifecycle_home" \
    AI_BROWSER_CONTROL_CHROMEOS_TOKEN_FILE="$lifecycle_token_file" \
    AI_BROWSER_CONTROL_CHROMEOS_CLI="$lifecycle_cli" \
    AI_BROWSER_CONTROL_CHROMEOS_CONNECT_HELPER=/bin/true \
    AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR="$lifecycle_state" \
    AI_BROWSER_CONTROL_CHROMEOS_POLL_INTERVAL=0.1 \
    AI_BROWSER_CONTROL_CHROMEOS_RECONNECT_DELAY=0.1 \
    FAKE_BROWSER_STATE="$lifecycle_browser_state" \
    FAKE_ATTACH_COUNT="$lifecycle_attach_count" \
    "$root/bin/ai-browser-control-chromeos" disconnect >/dev/null 2>&1 || true
  rm -rf "$cache_dir"
}
trap cleanup EXIT

bash -n \
  "$root/bin/ai-browser-control-chromeos" \
  "$root/scripts/setup.sh" \
  "$root/scripts/doctor.sh" \
  "$root/scripts/test.sh"

PYTHONPYCACHEPREFIX="$cache_dir" python3 -m py_compile \
  "$root/bin/ai-browser-control-chromeos-connect" \
  "$root/scripts/summarize.py"
node --check "$root/scripts/summarizeFeed.js"
python3 -m json.tool "$root/evals/evals.json" >/dev/null

python3 - "$root" <<'PY'
from __future__ import annotations

import pathlib
import importlib.util
from importlib.machinery import SourceFileLoader
import re
import sys

root = pathlib.Path(sys.argv[1])
skill = (root / "SKILL.md").read_text()
if not skill.startswith("---\n"):
    raise SystemExit("SKILL.md is missing YAML frontmatter")
frontmatter = skill.split("---\n", 2)[1]
for field in ("name:", "description:"):
    if field not in frontmatter:
        raise SystemExit(f"SKILL.md frontmatter is missing {field}")

for markdown_file in (root / "README.md", root / "SKILL.md"):
    text = markdown_file.read_text()
    for target in re.findall(r"\[[^]]+\]\(([^)]+)\)", text):
        if "://" in target or target.startswith("#"):
            continue
        path = (markdown_file.parent / target.split("#", 1)[0]).resolve()
        if not path.exists():
            raise SystemExit(f"Broken relative link in {markdown_file.name}: {target}")

helper_path = root / "bin" / "ai-browser-control-chromeos-connect"
loader = SourceFileLoader("chromeos_handoff", str(helper_path))
spec = importlib.util.spec_from_loader("chromeos_handoff", loader)
if spec is None or spec.loader is None:
    raise SystemExit("Could not load the ChromeOS handoff helper")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
page = helper.build_page(
    f"chrome-extension://{helper.EXTENSION_ID}/connect.html?ws=127.0.0.1",
    helper.DEFAULT_HANDOFF_TIMEOUT_SECONDS,
).decode()
if 'id="countdown">180</span>' not in page or "const timeout = 180;" not in page:
    raise SystemExit("The handoff page countdown does not match its 180-second deadline")
PY

"$root/scripts/setup.sh" --help >/dev/null

fake_bin="$cache_dir/fake-bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/xdg-open" <<'SH'
#!/bin/sh
exit 0
SH
chmod 700 "$fake_bin/xdg-open"
timeout 4 env \
  PATH="$fake_bin" \
  AI_BROWSER_CONTROL_CHROMEOS_HANDOFF_TIMEOUT=1 \
  /usr/bin/python3 "$root/bin/ai-browser-control-chromeos-connect" \
  "chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/connect.html?ws=127.0.0.1"

mkdir -p "$lifecycle_home"
printf '%s\n' 'test-token-not-secret' >"$lifecycle_token_file"
chmod 600 "$lifecycle_token_file"

cat >"$lifecycle_cli" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

shift
command="${1:-}"
case "$command" in
  list)
    if [[ -r "$FAKE_BROWSER_STATE" ]]; then
      printf '%s\n' \
        '### Browsers' \
        '- chromeos:' \
        '  - status: open' \
        '  - browser-type: chrome (attached)'
    else
      printf '%s\n' '### Browsers' '  (no browsers)'
    fi
    ;;
  attach)
    count=0
    [[ ! -r "$FAKE_ATTACH_COUNT" ]] || count="$(<"$FAKE_ATTACH_COUNT")"
    printf '%s\n' "$((count + 1))" >"$FAKE_ATTACH_COUNT"
    sleep "${FAKE_ATTACH_DELAY:-3}"
    printf '%s\n' 'open' >"$FAKE_BROWSER_STATE"
    printf 'relay token: %s\n' "$PLAYWRIGHT_MCP_EXTENSION_TOKEN"
    ;;
  detach)
    rm -f "$FAKE_BROWSER_STATE"
    ;;
  *)
    printf 'unsupported fake command: %s\n' "$command" >&2
    exit 2
    ;;
esac
SH
chmod 700 "$lifecycle_cli"

lifecycle_env=(
  HOME="$lifecycle_home"
  AI_BROWSER_CONTROL_CHROMEOS_TOKEN_FILE="$lifecycle_token_file"
  AI_BROWSER_CONTROL_CHROMEOS_CLI="$lifecycle_cli"
  AI_BROWSER_CONTROL_CHROMEOS_CONNECT_HELPER=/bin/true
  AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR="$lifecycle_state"
  AI_BROWSER_CONTROL_CHROMEOS_POLL_INTERVAL=0.1
  AI_BROWSER_CONTROL_CHROMEOS_RECONNECT_DELAY=0.1
  FAKE_BROWSER_STATE="$lifecycle_browser_state"
  FAKE_ATTACH_COUNT="$lifecycle_attach_count"
  FAKE_ATTACH_DELAY=3
)

set +e
invalid_output="$(env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" connect --persistant 2>&1)"
invalid_status=$?
set -e
[[ $invalid_status -eq 2 ]]
[[ "$invalid_output" == *'Unsupported connect argument: --persistant'* ]]
[[ ! -e "$lifecycle_state/connect-chromeos.pid" ]]

connect_output="$(env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" connect)"
[[ "$connect_output" == *'Background connection started'* ]]
first_pid="$(<"$lifecycle_state/connect-chromeos.pid")"
first_command="$(tr '\0' ' ' <"/proc/$first_pid/cmdline")"
[[ "$first_command" != *'--persistent'* ]]
connect_output="$(env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" connect)"
[[ "$connect_output" == *'Background connection is already running'* ]]
[[ "$(<"$lifecycle_state/connect-chromeos.pid")" == "$first_pid" ]]
env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" wait 5 >/dev/null
status_output="$(env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" status)"
[[ "$status_output" == connected:* ]]
connect_output="$(env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" connect)"
[[ "$connect_output" == *'is already connected'* ]]
log_output="$(env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" logs 40)"
[[ "$log_output" == *'[REDACTED]'* ]]
[[ "$log_output" != *'test-token-not-secret'* ]]
env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" disconnect >/dev/null
if env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" status >/dev/null; then
  printf '%s\n' 'Expected disconnected status to return nonzero.' >&2
  exit 1
fi

wait_for_attach_count() {
  local target="$1" count attempt
  for ((attempt = 0; attempt < 100; attempt++)); do
    count=0
    [[ ! -r "$lifecycle_attach_count" ]] || count="$(<"$lifecycle_attach_count")"
    if ((count >= target)) && [[ -r "$lifecycle_browser_state" ]]; then
      return 0
    fi
    sleep 0.1
  done
  printf 'Timed out waiting for fake attach count %s.\n' "$target" >&2
  tail -n 40 "$lifecycle_state/connect-chromeos.log" >&2 || true
  if [[ -r "$lifecycle_state/connect-chromeos.pid" ]]; then
    ps -o pid,ppid,state,args -p "$(<"$lifecycle_state/connect-chromeos.pid")" >&2 || true
  fi
  return 1
}

persistent_env=("${lifecycle_env[@]}" FAKE_ATTACH_DELAY=0.1)
connect_output="$(env "${persistent_env[@]}" "$root/bin/ai-browser-control-chromeos" connect --persistent)"
[[ "$connect_output" == *'Background connection started'* ]]
persistent_pid="$(<"$lifecycle_state/connect-chromeos.pid")"
persistent_command="$(tr '\0' ' ' <"/proc/$persistent_pid/cmdline")"
[[ "$persistent_command" == *'--persistent'* ]]
wait_for_attach_count 2
rm -f "$lifecycle_browser_state"
wait_for_attach_count 3
rm -f "$lifecycle_browser_state"
wait_for_attach_count 4
env "${persistent_env[@]}" "$root/bin/ai-browser-control-chromeos" disconnect >/dev/null

rm -f "$lifecycle_browser_state"
foreground_log="$cache_dir/foreground.log"
env "${persistent_env[@]}" \
  "$root/bin/ai-browser-control-chromeos" connect-foreground --persistent \
  >"$foreground_log" 2>&1 &
foreground_pid=$!
for ((attempt = 0; attempt < 50; attempt++)); do
  [[ -r "$lifecycle_state/connect-chromeos.pid" ]] && break
  sleep 0.1
done
[[ "$(<"$lifecycle_state/connect-chromeos.pid")" == "$foreground_pid" ]]
foreground_command="$(tr '\0' ' ' <"/proc/$foreground_pid/cmdline")"
[[ "$foreground_command" == *'connect-foreground --persistent'* ]]
set +e
status_output="$(env "${persistent_env[@]}" "$root/bin/ai-browser-control-chromeos" status)"
status_code=$?
set -e
[[ $status_code -eq 2 || $status_code -eq 0 ]]
[[ "$status_output" == connecting:* || "$status_output" == connected:* ]]
wait_for_attach_count 5
env "${persistent_env[@]}" "$root/bin/ai-browser-control-chromeos" disconnect >/dev/null
for ((attempt = 0; attempt < 50; attempt++)); do
  ! kill -0 "$foreground_pid" 2>/dev/null && break
  sleep 0.1
done
! kill -0 "$foreground_pid" 2>/dev/null
[[ "$(cat "$foreground_log")" == *'Foreground connection supervisor started'* ]]

snapshot_file="$cache_dir/feed-snapshot.yml"
cat >"$snapshot_file" <<'YAML'
- article "Feed post":
  - paragraph [ref=e1]: Andrea Zonca
  - text: 2h •
  - paragraph [ref=e2]: This is the post body.
  - button "12 reactions"
  - button "3 comments"
  - button "2 reposts"
YAML
summary_output="$(python3 "$root/scripts/summarize.py" "$snapshot_file")"
[[ "$summary_output" == *'Andrea Zonca (2h •)'* ]]
[[ "$summary_output" == *'This is the post body.'* ]]
[[ "$summary_output" == *'12 reactions, 3 comments, 2 reposts'* ]]

SUMMARY_SCRIPT="$root/scripts/summarize.py" python3 <<'PY'
import importlib.util
import json
import os
from importlib.machinery import SourceFileLoader

loader = SourceFileLoader("feed_summary", os.environ["SUMMARY_SCRIPT"])
spec = importlib.util.spec_from_loader("feed_summary", loader)
if spec is None or spec.loader is None:
    raise SystemExit("Could not load the feed summarizer")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
result = module.summarize_from_eval(json.dumps([{
    "author": "Andrea Zonca",
    "time": "2h",
    "text": "Post text",
    "reactions": "12",
    "comments": "3",
    "reposts": "2",
}]))
for expected in ("Andrea Zonca (2h)", "Post text", "12 reactions, 3 comments, 2 reposts"):
    if expected not in result:
        raise SystemExit(f"Eval summary is missing: {expected}")
PY

SUMMARIZE_FEED_JS="$root/scripts/summarizeFeed.js" node <<'JS'
const fs = require('fs');
const elements = {
  'strong, [data-view-name="profile-card-badge"]': {innerText: 'Andrea Zonca'},
  'time, span[dir="auto"]': {innerText: '2h'},
  'span[dir="auto"], div[data-view-name="feed-shared-social-action-renderer"]': {innerText: 'Post text'}
};
const article = {
  innerText: 'Post text\n12 reactions\n3 comments\n2 reposts',
  querySelector: selector => elements[selector] || null
};
global.document = {querySelectorAll: () => [article]};
const result = eval(fs.readFileSync(process.env.SUMMARIZE_FEED_JS, 'utf8'));
if (!Array.isArray(result) || result.length !== 1) process.exit(1);
if (result[0].text !== 'Post text') process.exit(1);
if (result[0].reactions !== '12' || result[0].comments !== '3' || result[0].reposts !== '2') process.exit(1);
JS

printf '%s\n' 'All skill checks passed.'
