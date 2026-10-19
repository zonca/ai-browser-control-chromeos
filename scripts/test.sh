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
lifecycle_shim_port="$(
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"
lifecycle_shim_pid_file="$lifecycle_state/shim-${lifecycle_session}.pid"

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
  "$root/bin/ai-browser-control-chromeos-relay-shim" \
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
node --check "$root/bin/ai-browser-control-chromeos-relay-shim"
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
        "ai-browser-control-chromeos verify",
        "never join `status`",
        "Missing mcpRelayUrl parameter in URL",
        "Failed to connect to MCP relay: WebSocket error",
        "remove the entire",
        "mcpRelayUrl",
        "Do not invoke raw `playwright-cli attach`",
        "references/agent-runbook.md",
        "Copy stable connect address",
        "relay shim",
        "Failure in OpenUrl",
    ),
    "references/agent-runbook.md": (
        "Deterministic start sequence",
        "Cross-process verification",
        "ai-browser-control-chromeos verify",
        "Do not combine lifecycle commands",
        "Exit 3",
        "Exit 124",
        "keep the existing supervisor",
        "rerun `status`, and connect once only if now disconnected",
        "AI_BROWSER_CONTROL_CHROMEOS_SESSION=research",
        "Never substitute raw `playwright-cli attach`",
        "Copy stable connect address",
        "Relay shim ready",
        "AI_BROWSER_CONTROL_CHROMEOS_SHIM_PORT",
        "AI_BROWSER_CONTROL_CHROMEOS_ATTACH_EXTENSION_TIMEOUT",
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
if "copy-stable" in page:
    raise SystemExit("The classic page must not offer the bookmark flow")

# Relay publication and stable bookmark address construction.
import json
import os
import tempfile
from urllib.parse import parse_qs as url_parse_qs
from urllib.parse import urlparse

tokenized_url = helper.normalize_connection_url(
    f"chrome-extension://{helper.EXTENSION_ID}/connect.html"
    "?mcpRelayUrl=ws%3A%2F%2F127.0.0.1%3A42281%2Fextension%2F4968ba0f"
    "&protocolVersion=2&token=not-a-real-token"
)
relay = helper.relay_url_from(tokenized_url)
if relay != "ws://127.0.0.1:42281/extension/4968ba0f":
    raise SystemExit(f"Unexpected relay address: {relay}")

stable = helper.stable_connection_url(tokenized_url, 45731)
if stable is None:
    raise SystemExit("A tokenized connection URL must produce a stable address")
parsed_stable = urlparse(stable)
if parsed_stable.scheme != "chrome-extension" or parsed_stable.netloc != helper.EXTENSION_ID:
    raise SystemExit(f"Unexpected stable address scheme: {stable}")
stable_query = url_parse_qs(parsed_stable.query)
inner = urlparse(stable_query["mcpRelayUrl"][0])
if inner.hostname != "127.0.0.1" or inner.port != 45731 or inner.path != "/stable":
    raise SystemExit(f"Unexpected stable relay address: {stable_query['mcpRelayUrl'][0]}")
if url_parse_qs(inner.query).get("token") != ["not-a-real-token"]:
    raise SystemExit("The stable relay address is missing the token")
if stable_query.get("protocolVersion") != ["2"] or stable_query.get("token") != ["not-a-real-token"]:
    raise SystemExit(f"The stable address lost engine parameters: {stable}")
if helper.stable_connection_url(normalized_url, 45731) is not None:
    raise SystemExit("A URL without a token must not produce a stable address")

stable_page = helper.build_page(
    tokenized_url, helper.DEFAULT_HANDOFF_TIMEOUT_SECONDS, stable_url=stable
).decode()
for expected in (
    "Connect AI</strong> bookmark",
    "copy-stable",
    "fetch('/state')",
    "fetch('/connected'",
    "Copy browser connection address",
):
    if expected not in stable_page:
        raise SystemExit(f"The bookmark handoff page is missing: {expected}")
if json.dumps(stable) not in stable_page:
    raise SystemExit("The bookmark handoff page does not embed the stable address")

publish_dir = tempfile.mkdtemp()
os.environ["AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR"] = publish_dir
os.environ["AI_BROWSER_CONTROL_CHROMEOS_SESSION"] = "unittest"
published = helper.write_relay_url(tokenized_url)
expected_path = os.path.join(publish_dir, "handoff-unittest.url")
if published != expected_path or not os.path.isfile(expected_path):
    raise SystemExit(f"Unexpected relay URL file: {published}")
with open(expected_path) as source:
    if source.read().strip() != relay:
        raise SystemExit("The published relay address does not match the connection URL")
if os.stat(expected_path).st_mode & 0o777 != 0o600:
    raise SystemExit("The published relay address must be mode 600")
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

# Relay shim: token validation, stable-path forwarding, upstream rewrite, lifecycle.
shim_state="$cache_dir/shim-state"
mkdir -p "$shim_state"
printf '%s\n' 'shim-test-token' >"$cache_dir/shim-token"
chmod 600 "$cache_dir/shim-token"
python3 - "$root" "$shim_state" "$cache_dir/shim-token" <<'PY'
import base64
import hashlib
import json
import os
import secrets
import socket
import subprocess
import sys
import threading
import time
import urllib.request

root, state_dir, token_file = sys.argv[1], sys.argv[2], sys.argv[3]
shim_script = os.path.join(root, "bin", "ai-browser-control-chromeos-relay-shim")
session = "shimtest"
token = "shim-test-token"


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


class FakeUpstream(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.seen_paths = []
        self.sock = socket.socket()
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", 0))
        self.port = self.sock.getsockname()[1]
        self.sock.listen(8)

    def run(self):
        while True:
            try:
                conn, _ = self.sock.accept()
            except OSError:
                return
            threading.Thread(target=self.serve, args=(conn,), daemon=True).start()

    def serve(self, conn):
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = conn.recv(4096)
            if not chunk:
                conn.close()
                return
            data += chunk
        path = data.split(b"\r\n")[0].decode().split(" ")[1]
        self.seen_paths.append(path)
        conn.sendall(
            b"HTTP/1.1 101 Switching Protocols\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n"
            b"Sec-WebSocket-Accept: placeholder\r\n\r\n"
        )
        conn.sendall(b"UPSTREAM-SAW:" + path.encode() + b"\r\n")
        try:
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                conn.sendall(chunk)
        except OSError:
            pass
        finally:
            conn.close()


def ws_connect(port, path):
    key = base64.b64encode(secrets.token_bytes(16)).decode()
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    lines = [
        f"GET {path} HTTP/1.1",
        f"Host: 127.0.0.1:{port}",
        "Upgrade: websocket",
        "Connection: Upgrade",
        f"Sec-WebSocket-Key: {key}",
        "Sec-WebSocket-Version: 13",
        "Origin: chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm",
    ]
    s.sendall(("\r\n".join(lines) + "\r\n\r\n").encode())
    return s


def read_head(s):
    s.settimeout(5)
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = s.recv(4096)
        if not chunk:
            break
        data += chunk
    head, _, rest = data.partition(b"\r\n\r\n")
    return head, rest


shim_port = free_port()
env = dict(os.environ)
env.update(
    AI_BROWSER_CONTROL_CHROMEOS_SHIM_PORT=str(shim_port),
    AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR=state_dir,
    AI_BROWSER_CONTROL_CHROMEOS_SESSION=session,
    AI_BROWSER_CONTROL_CHROMEOS_TOKEN_FILE=token_file,
)
shim = subprocess.Popen(
    ["node", shim_script], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
)
url_file = os.path.join(state_dir, f"handoff-{session}.url")
try:
    deadline = time.time() + 5
    while True:
        try:
            status = json.load(urllib.request.urlopen(f"http://127.0.0.1:{shim_port}/status", timeout=1))
            break
        except OSError:
            if time.time() > deadline:
                raise SystemExit("The relay shim did not start listening")
            time.sleep(0.1)
    if status["session"] != session or status["upstreamReady"] or status["activeConnections"]:
        raise SystemExit(f"Unexpected shim status before handoff: {status}")

    s = ws_connect(shim_port, "/stable?token=" + token)
    head, _ = read_head(s)
    if not head.startswith(b"HTTP/1.1 503"):
        raise SystemExit("A missing upstream must be rejected with 503")
    s.close()

    upstream = FakeUpstream()
    upstream.start()
    with open(url_file, "w") as output:
        output.write(f"ws://127.0.0.1:{upstream.port}/extension/4968ba0f-0000-0000-0000-000000000000\n")
    os.chmod(url_file, 0o600)

    s = ws_connect(shim_port, "/stable?token=wrong-token")
    head, _ = read_head(s)
    if not head.startswith(b"HTTP/1.1 403"):
        raise SystemExit("An invalid token must be rejected with 403")
    s.close()

    s = ws_connect(shim_port, "/not-stable?token=" + token)
    head, _ = read_head(s)
    if not head.startswith(b"HTTP/1.1 404"):
        raise SystemExit("An unexpected path must be rejected with 404")
    s.close()

    s = ws_connect(shim_port, "/stable?token=" + token)
    head, rest = read_head(s)
    if not head.startswith(b"HTTP/1.1 101"):
        raise SystemExit(f"The shim did not proxy the upgrade: {head[:60]!r}")
    deadline = time.time() + 5
    while b"UPSTREAM-SAW:" not in rest and time.time() < deadline:
        chunk = s.recv(4096)
        if not chunk:
            break
        rest += chunk
    if b"UPSTREAM-SAW:/extension/4968ba0f-0000-0000-0000-000000000000" not in rest:
        raise SystemExit("The upstream did not receive the rewritten relay path")
    s.sendall(b"roundtrip")
    echoed = b""
    deadline = time.time() + 5
    while b"roundtrip" not in echoed and time.time() < deadline:
        chunk = s.recv(4096)
        if not chunk:
            break
        echoed += chunk
    if b"roundtrip" not in echoed:
        raise SystemExit("Bytes did not flow back through the shim")
    s.close()
    time.sleep(0.3)
    status = json.load(urllib.request.urlopen(f"http://127.0.0.1:{shim_port}/status", timeout=1))
    if status["activeConnections"] != 0 or not status["upstreamReady"]:
        raise SystemExit(f"Unexpected shim status after disconnect: {status}")

    # A dead upstream must fail cleanly instead of accepting the upgrade.
    dead_port = free_port()
    with open(url_file, "w") as output:
        output.write(f"ws://127.0.0.1:{dead_port}/extension/deadbeef\n")
    s = ws_connect(shim_port, "/stable?token=" + token)
    head, _ = read_head(s)
    if not head.startswith(b"HTTP/1.1 503"):
        raise SystemExit("A dead upstream must be rejected with 503")
    s.close()
finally:
    shim.terminate()
    try:
        shim.wait(timeout=5)
    except subprocess.TimeoutExpired:
        shim.kill()
        raise SystemExit("The relay shim did not stop on SIGTERM")
print("relay shim checks passed")
PY
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
health_mode="$AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR/fake-health-mode"
printf '%s\n' "$PWD" >>"$AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR/fake-cwds"

case "$command" in
  list)
    printf 'Health checks must not invoke the registry-pruning list command.\n' >&2
    exit 99
    ;;
  attach)
    count=0
    [[ ! -r "$attach_count" ]] || count="$(<"$attach_count")"
    printf '%s\n' "$((count + 1))" >"$attach_count"
    printf '%s pid=%s ppid=%s attach-start count=%s\n' \
      "$(date +%s.%N)" "$$" "$PPID" "$((count + 1))" >>"$trace"
    printf '%s\n' "${PWTEST_EXTENSION_CONNECT_TIMEOUT:-missing}" \
      >"$AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR/fake-attach-timeout"
    printf 'ws://127.0.0.1:9/extension/fake-upstream\n' \
      >"$AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR/handoff-${session}.url"
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
  tab-list)
    mode=healthy
    [[ ! -r "$health_mode" ]] || mode="$(<"$health_mode")"
    printf '%s pid=%s health-mode=%s\n' "$(date +%s.%N)" "$$" "$mode" >>"$trace"
    case "$mode" in
      error) printf 'Transient transport error\n' >&2; exit 1 ;;
      timeout) sleep 10 ;;
    esac
    if [[ ! -r "$browser_state" ]] || (( $(date +%s%N) < $(cat "$list_ready_at" 2>/dev/null || printf 0) )); then
      printf "The browser '%s' is not open.\n" "$session" >&2
      exit 1
    fi
    printf '%s pid=%s verify-tab-list\n' "$(date +%s.%N)" "$$" >>"$trace"
    printf '%s\n' 'tab 0: Example (https://example.com)'
    ;;
  snapshot)
    printf '%s pid=%s verify-snapshot\n' "$(date +%s.%N)" "$$" >>"$trace"
    printf '%s\n' '- document "Example"'
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
  AI_BROWSER_CONTROL_CHROMEOS_HEALTH_TIMEOUT=1
  AI_BROWSER_CONTROL_CHROMEOS_SHIM_PORT="$lifecycle_shim_port"
  AI_BROWSER_CONTROL_CHROMEOS_ATTACH_EXTENSION_TIMEOUT=77
)

shim_listening() {
  (exec 3<>"/dev/tcp/127.0.0.1/$lifecycle_shim_port") 2>/dev/null
}

wait_for_shim_listening() {
  local attempt
  for ((attempt = 0; attempt < 100; attempt++)); do
    if shim_listening; then
      return 0
    fi
    sleep 0.05
  done
  printf 'Timed out waiting for the relay shim on port %s.\n' "$lifecycle_shim_port" >&2
  return 1
}

wait_for_shim_stopped() {
  local attempt
  for ((attempt = 0; attempt < 100; attempt++)); do
    if ! shim_listening; then
      return 0
    fi
    sleep 0.05
  done
  printf 'The relay shim is still listening on port %s after shutdown.\n' "$lifecycle_shim_port" >&2
  return 1
}

printf '%s\n' open >"$lifecycle_browser_state"
verify_output="$(env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" verify)"
[[ "$verify_output" == *'Verification 1/2'* ]]
[[ "$verify_output" == *'tab 0: Example'* ]]
[[ "$verify_output" == *'Verification 2/2'* ]]
[[ "$verify_output" == *'- document "Example"'* ]]
[[ "$verify_output" == *'Browser-control verification passed'* ]]
mapfile -t verify_pids < <(awk '
  /verify-tab-list|verify-snapshot/ {
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^pid=/) {
        sub(/^pid=/, "", $i)
        print $i
      }
    }
  }
' "$lifecycle_state/fake-trace")
[[ ${#verify_pids[@]} -eq 2 ]]
[[ "${verify_pids[0]}" != "${verify_pids[1]}" ]]

rm -f "$lifecycle_browser_state"

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

check_inconclusive_health() {
  local expected_pid="$1" before attempts errors_before
  errors_before="$(awk '/health-mode=error/ {n++} END {print n+0}' "$lifecycle_state/fake-trace")"
  before="$(<"$lifecycle_attach_count")"
  printf '%s\n' error >"$lifecycle_state/fake-health-mode"
  # More than the old three-miss threshold must never end the supervisor.
  for ((attempts = 0; attempts < 100; attempts++)); do
    if (( $(awk '/health-mode=error/ {n++} END {print n+0}' "$lifecycle_state/fake-trace") >= errors_before + 5 )); then
      break
    fi
    sleep 0.05
  done
  ((attempts < 100))
  kill -0 "$expected_pid"
  [[ "$(<"$lifecycle_attach_count")" == "$before" ]]
  [[ "$(<"$lifecycle_pid_file")" == "$expected_pid" ]]

  # A hung probe must time out without killing the relay or starting a handoff.
  printf '%s\n' timeout >"$lifecycle_state/fake-health-mode"
  sleep 1.5
  kill -0 "$expected_pid"
  [[ "$(<"$lifecycle_attach_count")" == "$before" ]]
  rm -f "$lifecycle_state/fake-health-mode"
  env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" wait 5 >/dev/null
  [[ "$(<"$lifecycle_attach_count")" == "$before" ]]
  sleep 0.2
  kill -0 "$expected_pid"
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
  [[ "$(<"$lifecycle_state/fake-attach-timeout")" == $((77 * 1000)) ]]
  wait_for_shim_listening
  shim_status_session="$(
    python3 - "$lifecycle_shim_port" <<'PY'
import json
import sys
import urllib.request
print(json.load(urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/status", timeout=2))["session"])
PY
  )"
  [[ "$shim_status_session" == "$lifecycle_session" ]]
  log_output="$(env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" logs 40)"
  [[ "$log_output" == *'[REDACTED]'* ]]
  [[ "$log_output" != *'test-token-not-secret'* ]]
  check_inconclusive_health "$first_pid"
  wait_for_shim_listening
  env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" disconnect >/dev/null
  wait_for_shim_stopped

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
    wait_for_shim_listening
    env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" disconnect >/dev/null
    wait_for_shim_stopped
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
  wait_for_shim_listening
  env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" disconnect >/dev/null
  wait_for_shim_stopped
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
check_inconclusive_health "$foreground_pid"
wait_for_shim_listening
env "${lifecycle_env[@]}" AI_BROWSER_CONTROL_CHROMEOS_SUPERVISOR=foreground \
  "$root/bin/ai-browser-control-chromeos" disconnect >/dev/null
for _ in {1..50}; do
  ! kill -0 "$foreground_pid" 2>/dev/null && break
  sleep 0.05
done
! kill -0 "$foreground_pid" 2>/dev/null
wait_for_shim_stopped
[[ "$(cat "$foreground_log")" == *'Foreground connection supervisor starting'* ]]

# A hard-killed supervisor cannot run its cleanup trap; the shim watchdog
# must notice the dead parent and exit by itself.
env "${lifecycle_env[@]}" AI_BROWSER_CONTROL_CHROMEOS_SUPERVISOR=foreground \
  "$root/bin/ai-browser-control-chromeos" connect-foreground --persistent \
  >"$foreground_log" 2>&1 &
foreground_pid=$!
for _ in {1..50}; do
  [[ -r "$lifecycle_pid_file" ]] && break
  sleep 0.05
done
wait_for_attach_count "$((count_before + 2))" || exit 1
wait_for_shim_listening
kill -9 "$foreground_pid"
for _ in {1..50}; do
  ! kill -0 "$foreground_pid" 2>/dev/null && break
  sleep 0.05
done
for _ in {1..200}; do
  if ! shim_listening; then
    break
  fi
  sleep 0.05
done
if shim_listening; then
  printf '%s\n' 'The relay shim outlived a hard-killed supervisor.' >&2
  exit 1
fi

# Slow initial readiness must preserve normal supervision, not just persistent mode.
printf '%s\n' error >"$lifecycle_state/fake-health-mode"
env "${lifecycle_env[@]}" AI_BROWSER_CONTROL_CHROMEOS_SUPERVISOR=foreground \
  AI_BROWSER_CONTROL_CHROMEOS_ATTACH_READY_TIMEOUT=0 \
  "$root/bin/ai-browser-control-chromeos" connect-foreground \
  >"$foreground_log" 2>&1 &
foreground_pid=$!
for _ in {1..100}; do
  if grep -q 'preserving the relay while monitoring' "$foreground_log"; then
    break
  fi
  sleep 0.05
done
grep -q 'preserving the relay while monitoring' "$foreground_log"
check_inconclusive_health "$foreground_pid"
rm -f "$lifecycle_browser_state"
for _ in {1..100}; do
  ! kill -0 "$foreground_pid" 2>/dev/null && break
  sleep 0.05
done
! kill -0 "$foreground_pid" 2>/dev/null
grep -q 'Session closure confirmed' "$foreground_log"
[[ ! -e "$lifecycle_pid_file" ]]

# Commands invoked from unrelated caller directories share one stable workspace.
(cd /tmp; env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" status >/dev/null) || true
[[ "$(sort -u "$lifecycle_state/fake-cwds")" == "$lifecycle_state/cli-workspace" ]]

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
