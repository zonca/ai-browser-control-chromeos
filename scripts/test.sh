#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache_dir="$(mktemp -d)"
lifecycle_home="$cache_dir/home"
lifecycle_state="$cache_dir/state"
lifecycle_browser_state="$cache_dir/browser-state"
lifecycle_token_file="$cache_dir/extension-token"
lifecycle_cli="$cache_dir/playwright-cli"

cleanup() {
  HOME="$lifecycle_home" \
    AI_BROWSER_CONTROL_CHROMEOS_TOKEN_FILE="$lifecycle_token_file" \
    AI_BROWSER_CONTROL_CHROMEOS_CLI="$lifecycle_cli" \
    AI_BROWSER_CONTROL_CHROMEOS_CONNECT_HELPER=/bin/true \
    AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR="$lifecycle_state" \
    FAKE_BROWSER_STATE="$lifecycle_browser_state" \
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
  "$root/bin/ai-browser-control-chromeos-connect"
python3 -m json.tool "$root/evals/evals.json" >/dev/null

python3 - "$root" <<'PY'
from __future__ import annotations

import pathlib
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
PY

"$root/scripts/setup.sh" --help >/dev/null

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
    sleep 1
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
  FAKE_BROWSER_STATE="$lifecycle_browser_state"
)

connect_output="$(env "${lifecycle_env[@]}" "$root/bin/ai-browser-control-chromeos" connect)"
[[ "$connect_output" == *'Background connection started'* ]]
first_pid="$(<"$lifecycle_state/connect-chromeos.pid")"
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

printf '%s\n' 'All skill checks passed.'
