#!/usr/bin/env bash
set -uo pipefail

failures=0
warnings=0

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
warn() { printf 'WARN  %s\n' "$1"; warnings=$((warnings + 1)); }

if command -v node >/dev/null 2>&1; then
  node_major="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || printf 0)"
  if ((node_major >= 18)); then
    pass "Node.js $(node --version)"
  else
    fail "Node.js 18+ required; found $(node --version 2>/dev/null || printf unknown)"
  fi
else
  fail 'Node.js is missing'
fi

command -v npm >/dev/null 2>&1 && pass "npm $(npm --version)" || fail 'npm is missing'
command -v python3 >/dev/null 2>&1 && pass "Python $(python3 --version 2>&1)" || fail 'python3 is missing'
command -v garcon-url-handler >/dev/null 2>&1 && pass 'ChromeOS garcon-url-handler found' || warn 'garcon-url-handler not found'
[[ -d /mnt/chromeos ]] && pass 'ChromeOS mount detected' || warn '/mnt/chromeos not detected'

if command -v playwright-cli >/dev/null 2>&1; then
  pass "Browser engine CLI $(playwright-cli --version)"
else
  fail 'playwright-cli is missing'
fi

if command -v ai-browser-control-chromeos >/dev/null 2>&1; then
  pass "Runtime wrapper $(command -v ai-browser-control-chromeos)"
else
  fail 'ai-browser-control-chromeos wrapper is missing from PATH'
fi

if command -v ai-browser-control-chromeos-connect >/dev/null 2>&1; then
  pass "ChromeOS handoff helper $(command -v ai-browser-control-chromeos-connect)"
else
  fail 'ai-browser-control-chromeos-connect helper is missing from PATH'
fi

token_file="${AI_BROWSER_CONTROL_CHROMEOS_TOKEN_FILE:-$HOME/.config/ai-browser-control-chromeos/extension-token}"
if [[ -s "$token_file" ]]; then
  mode="$(stat -c '%a' "$token_file" 2>/dev/null || printf unknown)"
  if [[ "$mode" == 600 ]]; then
    pass "Extension token file exists with mode 600"
  else
    fail "Extension token file permissions are $mode; expected 600"
  fi
else
  fail "Extension token file is missing: $token_file"
fi

skill_path="${AGENT_SKILLS_DIR:-$HOME/.agents/skills}/ai-browser-control-chromeos/SKILL.md"
[[ -r "$skill_path" ]] && pass "Agent skill installed at ${skill_path%/SKILL.md}" || warn "Agent skill not found at ${skill_path%/SKILL.md}"

printf '\nManual check: confirm the required browser-control extension is installed in ChromeOS Chrome.\n'
printf 'Summary: %d failure(s), %d warning(s).\n' "$failures" "$warnings"
((failures == 0))
