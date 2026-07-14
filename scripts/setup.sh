#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill_parent="${AGENT_SKILLS_DIR:-$HOME/.agents/skills}"
install_skill=true
install_cli=true

usage() {
  cat <<'EOF'
Usage: ./scripts/setup.sh [options]

Options:
  --skill-dir DIR       Install the skill under DIR (default: ~/.agents/skills)
  --no-skill-install    Install only the browser runtime
  --skip-cli-install    Require an existing playwright-cli installation
  -h, --help            Show this help

The extension token is read from PLAYWRIGHT_MCP_EXTENSION_TOKEN or requested through
a hidden terminal prompt. It is never accepted as a command-line argument.
EOF
}

while (($#)); do
  case "$1" in
    --skill-dir)
      [[ $# -ge 2 ]] || { printf '%s\n' '--skill-dir requires a value' >&2; exit 2; }
      skill_parent="$2"
      shift 2
      ;;
    --no-skill-install)
      install_skill=false
      shift
      ;;
    --skip-cli-install)
      install_cli=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for command in node npm python3; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command" >&2
    exit 1
  fi
done

node_major="$(node -p 'Number(process.versions.node.split(".")[0])')"
if ((node_major < 18)); then
  printf 'Node.js 18 or newer is required; found %s.\n' "$(node --version)" >&2
  exit 1
fi

if ! command -v garcon-url-handler >/dev/null 2>&1; then
  printf '%s\n' 'Warning: garcon-url-handler was not found; this may not be a ChromeOS Crostini environment.' >&2
fi

if ! command -v playwright-cli >/dev/null 2>&1; then
  if [[ "$install_cli" == true ]]; then
    printf '%s\n' 'Installing @playwright/cli globally...'
    npm install -g "${PLAYWRIGHT_CLI_PACKAGE:-@playwright/cli@latest}"
  else
    printf '%s\n' 'playwright-cli is missing and --skip-cli-install was requested.' >&2
    exit 1
  fi
fi
bin_dir="$HOME/.local/bin"
config_dir="$HOME/.config/playwright-chromeos"
token_file="$config_dir/extension-token"
install -d -m 700 "$bin_dir" "$config_dir"
install -m 700 "$root/bin/playwright-chromeos" "$bin_dir/playwright-chromeos"
install -m 700 "$root/bin/playwright-chromeos-connect" "$bin_dir/playwright-chromeos-connect"

token="${PLAYWRIGHT_MCP_EXTENSION_TOKEN:-}"
if [[ -z "$token" && -r "$token_file" ]]; then
  token="$(<"$token_file")"
fi
if [[ -z "$token" ]]; then
  if [[ ! -t 0 ]]; then
    printf '%s\n' 'No extension token is available. Run setup interactively or set PLAYWRIGHT_MCP_EXTENSION_TOKEN securely.' >&2
    exit 1
  fi
  printf '%s\n' 'Install the official Playwright Extension in ChromeOS Chrome:'
  printf '%s\n' 'https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm'
  printf '%s\n' 'Open the extension and copy the token shown in its PLAYWRIGHT_MCP_EXTENSION_TOKEN instruction.'
  read -r -s -p 'Extension token (input hidden): ' token
  printf '\n'
fi

if [[ -z "$token" || "$token" == *$'\n'* ]]; then
  printf '%s\n' 'The extension token is empty or invalid.' >&2
  exit 1
fi

umask 077
printf '%s\n' "$token" >"$token_file"
chmod 600 "$token_file"

if [[ "$install_skill" == true ]]; then
  install -d "$skill_parent"
  skill_target="$skill_parent/playwright-chromeos"
  if [[ -L "$skill_target" ]]; then
    current_target="$(readlink -f "$skill_target" || true)"
    if [[ "$current_target" != "$root" ]]; then
      printf 'Refusing to replace existing skill link: %s -> %s\n' "$skill_target" "$current_target" >&2
      exit 1
    fi
  elif [[ -e "$skill_target" ]]; then
    printf 'Refusing to replace existing skill path: %s\n' "$skill_target" >&2
    exit 1
  else
    ln -s "$root" "$skill_target"
  fi
fi

printf '\nSetup complete.\n'
printf 'Playwright CLI: %s\n' "$(playwright-cli --version)"
printf 'Runtime command: %s\n' "$bin_dir/playwright-chromeos"
printf 'Token file: %s (mode %s)\n' "$token_file" "$(stat -c '%a' "$token_file")"
if [[ "$install_skill" == true ]]; then
  printf 'Skill: %s\n' "$skill_parent/playwright-chromeos"
fi
if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
  printf '\nAdd %s to PATH or start a new terminal before connecting.\n' "$bin_dir"
fi
printf '\nConnect once from a normal Linux terminal with: playwright-chromeos connect\n'
