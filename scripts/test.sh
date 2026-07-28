#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache_dir="$(mktemp -d)"
lifecycle_home="$cache_dir/home"
lifecycle_state="$cache_dir/state"
lifecycle_token_file="$cache_dir/extension-token"
lifecycle_cli="$cache_dir/playwright-cli"
lifecycle_session="test-${BASHPID}"
lifecycle_pid_file="$lifecycle_state/connect-${lifecycle_session}.pid"
lifecycle_log_file="$lifecycle_state/connect-${lifecycle_session}.log"
lifecycle_browser_state="$lifecycle_state/fake-browser-state"
lifecycle_attach_count="$lifecycle_state/fake-attach-count"
lifecycle_attach_delay="$lifecycle_state/fake-attach-delay"
lifecycle_unit="ai-browser-control-chromeos-${UID}-${lifecycle_session}.service"

cleanup() {
  HOME="$lifecycle_home" \
    AI_BROWSER_CONTROL_CHROMEOS_TOKEN_FILE="$lifecycle_token_file" \
    AI_BROWSER_CONTROL_CHROMEOS_SESSION="$lifecycle_session" \
    AI_BROWSER_CONTROL_CHROMEOS_CLI="$lifecycle_cli" \
    AI_BROWSER_CONTROL_CHROMEOS_CONNECT_HELPER=/bin/true \
    AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR="$lifecycle_state" \
    AI_BROWSER_CONTROL_CHROMEOS_POLL_INTERVAL=0.05 \
    AI_BROWSER_CONTROL_CHROMEOS_RECONNECT_DELAY=0.05 \
    "$root/bin/ai-browser-control-chromeos" disconnect >/dev/null 2>&1 || true
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user stop "$lifecycle_unit" >/dev/null 2>&1 || true
    systemctl --user reset-failed "$lifecycle_unit" >/dev/null 2>&1 || true
  fi
  rm -rf "$cache_dir"
}
trap cleanup EXIT

chmod 700 \
  "$root/bin/ai-browser-control-chromeos" \
  "$root/bin/ai-browser-control-chromeos-connect" \
  "$root/scripts/setup.sh" \
  "$root/scripts/doctor.sh" \
  "$root/scripts/test.sh"

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

import importlib.util
from importlib.machinery import SourceFileLoader
import pathlib
import re
import sys
from urllib.parse import unquote_plus

root = pathlib.Path(sys.argv[1])
skill = (root / "SKILL.md").read_text()
if not skill.startswith("---\n"):
    raise SystemExit("SKILL.md is missing YAML frontmatter")
frontmatter = skill.split("---\n", 2)[1]
for field in ("name:", "description:"):
    if field not in frontmatter:
        raise SystemExit(f"SKILL.md frontmatter is missing {field}")

for markdown_file in sorted(root.rglob("*.md")):
    text = markdown_file.read_text()
    for target in re.findall(r"\[[^]]+\]\(([^)]+)\)", text):
        if "://" in target or target.startswith("#"):
            continue
        path = (markdown_file.parent / target.split("#", 1)[0]).resolve()
        if not path.exists():
            raise SystemExit(
                f"Broken relative link in {markdown_file.relative_to(root)}: {target}"
            )

runbook = (root / "references" / "agent-runbook.md").read_text()
documentation_contract = {
    "SKILL.md": (
        "ai-browser-control-chromeos status",
        "Exit 2, `connecting`",
        "ai-browser-control-chromeos connect-foreground",
        "ai-browser-control-chromeos wait 180",
        "ai-browser-control-chromeos tab-list",
        "ai-browser-control-chromeos snapshot",
        "Missing mcpRelayUrl parameter in URL",
        "Failed to connect to MCP relay: WebSocket error",
        "Do not invoke raw `playwright-cli attach`",
        "references/agent-runbook.md",
    ),
    "references/agent-runbook.md": (
        "Deterministic start sequence",
        "Cross-process verification",
        "Run both commands as separate terminal invocations",
        "Exit 3",
        "Exit 124",
        "keep the existing supervisor",
        "rerun `status`, and connect once only if now disconnected",
        "AI_BROWSER_CONTROL_CHROMEOS_SESSION=research",
        "Never substitute raw `playwright-cli attach`",
    ),
}
documents = {"SKILL.md": skill, "references/agent-runbook.md": runbook}
for document, requirements in documentation_contract.items():
    for requirement in requirements:
        if requirement not in documents[document]:
            raise SystemExit(
                f"{document} is missing required agent guidance: {requirement}"
            )

helper_path = root / "bin" / "ai-browser-control-chromeos-connect"
loader = SourceFileLoader("chromeos_handoff", str(helper_path))
spec = importlib.util.spec_from_loader("chromeos_handoff", loader)
if spec is None or spec.loader is None:
    raise SystemExit("Could not load the ChromeOS handoff helper")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
normalized_url = helper.normalize_connection_url(
    f"chrome-extension://{helper.EXTENSION_ID}/connect.html"
    "?mcpRelayUrl=ws%3A%2F%2F127.0.0.1%2Fextension%2Ftest"
    "&client=%7B%22name%22%3A%22playwright-cli%22%7D"
)
normalized_client = re.search(r"[?&]client=([^&]+)", normalized_url)
if normalized_client is None:
    raise SystemExit("The normalized connection URL is missing the client label")
if '"name":"AI Browser Control"' not in unquote_plus(normalized_client.group(1)):
    raise SystemExit("The connection URL does not label the browser-control client")

page = helper.build_page(normalized_url, helper.DEFAULT_HANDOFF_TIMEOUT_SECONDS).decode()
for expected in (
    "Copy browser connection address",
    "navigator.clipboard.writeText(connectionUrl)",
    "fetch('/copied'",
):
    if expected not in page:
        raise SystemExit(f"The handoff page is missing: {expected}")
if "Session expires" in page or "countdown" in page:
    raise SystemExit("The handoff page still claims the relay expires on a UI timer")
PY

"$root/scripts/setup.sh" --help >/dev/null

fake_bin="$cache_dir/fake-bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/xdg-open" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
python3 - "$1" <<'PY'
import sys
import urllib.request

url = sys.argv[1]
with urllib.request.urlopen(url, timeout=2) as response:
    if response.status != 200:
        raise SystemExit("handoff page did not return HTTP 200")
request = urllib.request.Request(f"{url}copied", method="POST")
with urllib.request.urlopen(request, timeout=2) as response:
    if response.status != 204:
        raise SystemExit("handoff completion did not return HTTP 204")
PY
SH
chmod 700 "$fake_bin/xdg-open"
handoff_pid_file="$cache_dir/handoff.pid"
timeout 5 env \
  PATH="$fake_bin:/usr/bin:/bin" \
  AI_BROWSER_CONTROL_CHROMEOS_HANDOFF_TIMEOUT=3 \
  AI_BROWSER_CONTROL_CHROMEOS_HANDOFF_PID_FILE="$handoff_pid_file" \
  /usr/bin/python3 "$root/bin/ai-browser-control-chromeos-connect" \
  "chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/connect.html?mcpRelayUrl=ws%3A%2F%2F127.0.0.1%2Fextension%2Ftest"
[[ ! -e "$handoff_pid_file" ]]

set +e
missing_relay_output="$(
  /usr/bin/python3 "$root/bin/ai-browser-control-chromeos-connect" \
    "chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/connect.html" 2>&1
)"
missing_relay_status=$?
set -e
[[ $missing_relay_status -ne 0 ]]
[[ "$missing_relay_output" == *'missing one mcpRelayUrl'* ]]

mkdir -p "$lifecycle_home" "$lifecycle_state"
printf '%s\n' 'test-token-not-secret' >"$lifecycle_token_file"
chmod 600 "$lifecycle_token_file"
printf '%s\n' '0.2' >"$lifecycle_attach_delay"

cat >"$lifecycle_cli" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

session="${1#-s=}"
shift
command="${1:-}"
browser_state="$AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR/fake-browser-state"
attach_count="$AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR/fake-attach-count"
attach_delay="$AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR/fake-attach-delay"
list_ready_at="$AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR/fake-list-ready-at"
trace="$AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR/fake-trace"

case "$command" in
  list)
    now="$(date +%s%N)"
    ready_at=0
    [[ ! -r "$list_ready_at" ]] || ready_at="$(<"$list_ready_at")"
    if [[ -r "$browser_state" ]] && ((now >= ready_at)); then
      trace_state=present
    else
      trace_state=absent
    fi
    printf '%s pid=%s list state=%s\n' "$(date +%s.%N)" "$$" "$trace_state" >>"$trace"
    if [[ "$trace_state" == present ]]; then
      printf '%s\n' \
        '### Browsers' \
        "- $session:" \
        '  - status: open' \
        '  - browser-type: chrome (attached)'
    else
      printf '%s\n' '### Browsers' '  (no browsers)'
    fi
    ;;
  attach)
    count=0
    [[ ! -r "$attach_count" ]] || count="$(<"$attach_count")"
    printf '%s\n' "$((count + 1))" >"$attach_count"
    printf '%s pid=%s ppid=%s attach-start count=%s\n' \
      "$(date +%s.%N)" "$$" "$PPID" "$((count + 1))" >>"$trace"
    sleep "$(<"$attach_delay")"
    printf '%s\n' 'open' >"$browser_state"
    printf '%s\n' "$(( $(date +%s%N) + 250000000 ))" >"$list_ready_at"
    printf '%s pid=%s ppid=%s attach-open count=%s\n' \
      "$(date +%s.%N)" "$$" "$PPID" "$((count + 1))" >>"$trace"
    printf 'relay token: %s\n' "$PLAYWRIGHT_MCP_EXTENSION_TOKEN"
    ;;
  detach)
    printf '%s pid=%s detach\n' "$(date +%s.%N)" "$$" >>"$trace"
    rm -f "$browser_state" "$list_ready_at"
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
  AI_BROWSER_CONTROL_CHROMEOS_SESSION="$lifecycle_session"
  AI_BROWSER_CONTROL_CHROMEOS_CLI="$lifecycle_cli"
  AI_BROWSER_CONTROL_CHROMEOS_CONNECT_HELPER=/bin/true
  AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR="$lifecycle_state"
  AI_BROWSER_CONTROL_CHROMEOS_POLL_INTERVAL=0.05
  AI_BROWSER_CONTROL_CHROMEOS_RECONNECT_DELAY=0.05
  AI_BROWSER_CONTROL_CHROMEOS_ATTACH_READY_TIMEOUT=2
  AI_BROWSER_CONTROL_CHROMEOS_DISCONNECT_MISSES=3
)

set +e
invalid_output="$(env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" connect --persistant 2>&1)"
invalid_status=$?
set -e
[[ $invalid_status -eq 2 ]]
[[ "$invalid_output" == *'Unsupported connection argument: --persistant'* ]]
[[ ! -e "$lifecycle_pid_file" ]]

set +e
invalid_session_output="$(
  env "${lifecycle_env[@]}" AI_BROWSER_CONTROL_CHROMEOS_SESSION='../bad' \
    "$root/bin/ai-browser-control-chromeos" status 2>&1
)"
invalid_session_status=$?
set -e
[[ $invalid_session_status -eq 2 ]]
[[ "$invalid_session_output" == *'Invalid session name'* ]]

set +e
foreground_required="$(
  env "${lifecycle_env[@]}" AI_BROWSER_CONTROL_CHROMEOS_SUPERVISOR=foreground \
    "$root/bin/ai-browser-control-chromeos" connect 2>&1
)"
foreground_required_status=$?
set -e
[[ $foreground_required_status -eq 3 ]]
[[ "$foreground_required" == *'connect-foreground'* ]]
[[ ! -e "$lifecycle_pid_file" ]]

wait_for_attach_count() {
  local target="$1" count attempt
  for ((attempt = 0; attempt < 150; attempt++)); do
    count=0
    [[ ! -r "$lifecycle_attach_count" ]] || count="$(<"$lifecycle_attach_count")"
    if ((count >= target)) && [[ -r "$lifecycle_browser_state" ]]; then
      return 0
    fi
    sleep 0.05
  done
  printf 'Timed out waiting for fake attach count %s.\n' "$target" >&2
  printf 'Observed attach count: %s; browser state: %s.\n' \
    "$count" "$([[ -r "$lifecycle_browser_state" ]] && printf present || printf absent)" >&2
  tail -n 40 "$lifecycle_log_file" >&2 || true
  rg 'attach|detach|state=absent' "$lifecycle_state/fake-trace" >&2 || true
  for process_environ in /proc/[0-9]*/environ; do
    process_pid="${process_environ#/proc/}"
    process_pid="${process_pid%/environ}"
    [[ -r "$process_environ" ]] || continue
    grep -zFxq "AI_BROWSER_CONTROL_CHROMEOS_SESSION=$lifecycle_session" \
      "$process_environ" 2>/dev/null || continue
    ps -o pid,ppid,state,etime,args -p "$process_pid" >&2 || true
  done
  if [[ "$systemd_usable" == true ]]; then
    systemctl --user status "$lifecycle_unit" --no-pager >&2 || true
    journalctl --user-unit "$lifecycle_unit" --no-pager -n 80 >&2 || true
  fi
  return 1
}

systemd_usable=false
if command -v systemctl >/dev/null 2>&1 &&
   command -v systemd-run >/dev/null 2>&1 &&
   systemctl --user show-environment >/dev/null 2>&1; then
  systemd_usable=true
fi

if [[ "$systemd_usable" == true ]]; then
  connect_output="$(env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" connect)"
  [[ "$connect_output" == *'Durable connection service started'* ]]
  first_pid="$(systemctl --user show "$lifecycle_unit" -p MainPID --value)"
  [[ "$first_pid" =~ ^[1-9][0-9]*$ ]]
  [[ "$(<"$lifecycle_pid_file")" == "$first_pid" ]]
  first_parent="$(ps -o ppid= -p "$first_pid" | tr -d ' ')"
  [[ "$first_parent" != "$$" ]]

  connect_output="$(env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" connect)"
  [[ "$connect_output" == *'Connection supervisor is already running'* ||
     "$connect_output" == *'is already connected'* ]]
  [[ "$(systemctl --user show "$lifecycle_unit" -p MainPID --value)" == "$first_pid" ]]

  env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" wait 5 >/dev/null
  status_output="$(env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" status)"
  [[ "$status_output" == connected:* ]]
  log_output="$(env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" logs 40)"
  [[ "$log_output" == *'[REDACTED]'* ]]
  [[ "$log_output" != *'test-token-not-secret'* ]]
  env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" disconnect >/dev/null

  if env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" status >/dev/null; then
    printf '%s\n' 'Expected disconnected status to return nonzero.' >&2
    exit 1
  fi

  # Repeated cross-process starts prove that the user service owns the supervisor,
  # not the short-lived shell that invoked connect.
  printf '%s\n' '0.05' >"$lifecycle_attach_delay"
  for _ in {1..5}; do
    env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" connect >/dev/null
    env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" wait 5 >/dev/null
    env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" disconnect >/dev/null
  done

  count_before=0
  [[ ! -r "$lifecycle_attach_count" ]] || count_before="$(<"$lifecycle_attach_count")"
  connect_output="$(
    env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" connect --persistent
  )"
  [[ "$connect_output" == *'Durable connection service started'* ]]
  persistent_pid="$(systemctl --user show "$lifecycle_unit" -p MainPID --value)"
  persistent_command="$(tr '\0' ' ' <"/proc/$persistent_pid/cmdline")"
  [[ "$persistent_command" == *'__connect-supervisor --persistent'* ]]
  wait_for_attach_count "$((count_before + 1))" || exit 1
  env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" wait 5 >/dev/null
  rm -f "$lifecycle_browser_state"
  wait_for_attach_count "$((count_before + 2))" || exit 1
  env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" wait 5 >/dev/null
  rm -f "$lifecycle_browser_state"
  wait_for_attach_count "$((count_before + 3))" || exit 1
  env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" wait 5 >/dev/null
  env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" disconnect >/dev/null
else
  printf '%s\n' 'SKIP  durable systemd integration (user service manager unavailable)'
fi

rm -f "$lifecycle_browser_state"
printf '%s\n' '0.05' >"$lifecycle_attach_delay"
count_before=0
[[ ! -r "$lifecycle_attach_count" ]] || count_before="$(<"$lifecycle_attach_count")"
foreground_log="$cache_dir/foreground.log"
env "${lifecycle_env[@]}" AI_BROWSER_CONTROL_CHROMEOS_SUPERVISOR=foreground \
  "$root/bin/ai-browser-control-chromeos" connect-foreground --persistent \
  >"$foreground_log" 2>&1 &
foreground_pid=$!
for _ in {1..50}; do
  [[ -r "$lifecycle_pid_file" ]] && break
  sleep 0.05
done
[[ "$(<"$lifecycle_pid_file")" == "$foreground_pid" ]]
set +e
status_output="$(
  env "${lifecycle_env[@]}" AI_BROWSER_CONTROL_CHROMEOS_SUPERVISOR=foreground \
    "$root/bin/ai-browser-control-chromeos" status
)"
status_code=$?
set -e
[[ $status_code -eq 2 || $status_code -eq 0 ]]
[[ "$status_output" == connecting:* || "$status_output" == connected:* ]]
wait_for_attach_count "$((count_before + 1))" || exit 1
env "${lifecycle_env[@]}" AI_BROWSER_CONTROL_CHROMEOS_SUPERVISOR=foreground \
  "$root/bin/ai-browser-control-chromeos" wait 5 >/dev/null
env "${lifecycle_env[@]}" AI_BROWSER_CONTROL_CHROMEOS_SUPERVISOR=foreground \
  "$root/bin/ai-browser-control-chromeos" disconnect >/dev/null
for _ in {1..50}; do
  ! kill -0 "$foreground_pid" 2>/dev/null && break
  sleep 0.05
done
! kill -0 "$foreground_pid" 2>/dev/null
[[ "$(cat "$foreground_log")" == *'Foreground connection supervisor starting'* ]]

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
