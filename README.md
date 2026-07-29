# AI Browser Control for ChromeOS

Use an AI coding agent running inside a Chromebook Linux development environment
(Crostini) to control the user's existing ChromeOS Chrome window. The browser keeps
the user's normal profile, tabs, cookies, and interactive login state.

This repository contains both an agent skill and the small local bridge needed to
make the workflow practical.

## Motivation

Reproduce the `claude --chrome` experience on ChromeOS for any AI coding agent: the
human connects their normal Chrome browser and handles login or MFA, then the agent
continues in the same authenticated browser. This repository packages that human/AI
handoff as a reusable skill and persistent local bridge.

## How it works

```text
AI agent -> ai-browser-control-chromeos -> named browser-control daemon
                                      |
                                      v
                              Playwright extension
                                      |
                                      v
                         existing ChromeOS Chrome profile
```

The agent runs `connect`, which launches the relay under Crostini's user service
manager and returns immediately. The service survives the short terminal call that
started it. A small local page opens in Chrome. The user clicks Copy, pastes the
generated extension address into Chrome's address bar, and presses Enter. The agent
polls connection status and continues automatically. Later commands reuse the named
daemon without another Connect tab. The handoff identifies itself as
`AI Browser Control` instead of a generic Playwright client.

## Requirements

- A Chromebook with Linux development environment enabled.
- ChromeOS Chrome, not a separate Linux Chrome profile.
- Node.js 18 or newer and npm inside the Linux environment.
- Python 3 and `garcon-url-handler` inside Crostini.
- A working systemd user manager for durable background supervision. Environments
  without one can use the agent-managed foreground fallback.
- The official [Playwright Extension for Chrome](https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm).

The setup script installs `@playwright/cli` globally. It does not use `npx` during
normal operation.

## Installation (run by the agent)

The AI agent should execute these commands after the user authorizes installation.
They are shown here so the process remains auditable:

```bash
git clone https://github.com/zonca/ai-browser-control-chromeos.git
cd ai-browser-control-chromeos
./scripts/setup.sh
```

The setup script:

1. Checks Node.js, npm, Python, and the ChromeOS URL handler.
2. Permanently installs `@playwright/cli` if needed.
3. Installs `ai-browser-control-chromeos` and its URL handoff helper in `~/.local/bin`.
4. Prompts privately for the extension token and stores it with mode `600`.
5. Links this repository into `~/.agents/skills/ai-browser-control-chromeos` by default.

Use another agent skill directory when needed:

```bash
./scripts/setup.sh --skill-dir "$HOME/.claude/skills"
```

Or set `AGENT_SKILLS_DIR` before running setup. Use `--no-skill-install` when only
the browser command should be installed.

### OpenCode

OpenCode can auto-load skills from `~/.agents/skills`, but some releases do not
follow a directory symlink created there. If `opencode debug skill` does not list
`ai-browser-control-chromeos`, add the repository checkout as an explicit skill
path in `~/.config/opencode/opencode.json`:

```json
{
  "skills": {
    "paths": ["/absolute/path/to/ai-browser-control-chromeos"]
  }
}
```

Merge this with the existing configuration instead of replacing other settings,
then restart OpenCode. Verify discovery with:

```bash
opencode debug skill | grep ai-browser-control-chromeos
```

### The extension token

Install the Playwright extension, open its connection screen, and copy the token
shown in the `PLAYWRIGHT_MCP_EXTENSION_TOKEN=...` instruction. The agent runs
`setup.sh`; enter the token only through its hidden prompt or a trusted secret
environment.

Do not paste the token into an AI conversation, issue, log, or repository. For
non-interactive setup, provide it through a trusted secret environment:

```bash
PLAYWRIGHT_MCP_EXTENSION_TOKEN="..." ./scripts/setup.sh
```

## How an agent should ask for prerequisites

The agent owns all terminal work: diagnostics, installation, setup, connection
services, status polling, browser commands, logs, and cleanup. The user only handles
actions that cannot safely be automated: installing the Chrome extension, entering
its token privately, interactive login/MFA, and approving consequential actions.

Recommended message:

> Please install the official Playwright Extension in ChromeOS Chrome and open it
> to copy the token it shows. I will run the setup and connection processes. Enter
> the token only through the secure prompt I open; do not paste it into this chat.
> Tell me when the extension is installed.

If only Node.js or npm is missing, tell the user exactly what the diagnostic found
and ask them to install Node.js 18+ in Crostini. Do not claim the extension is
installed merely because its Web Store page is reachable; Linux cannot reliably
inspect the ChromeOS browser profile.

When the connection page opens, ask:

> Click **Copy browser connection address**, then press **Ctrl+L**, **Ctrl+V**,
> and **Enter**. Tell me when the extension page says it is connected.

After that, the agent polls the connection service and continues. It must not ask
the user to run a terminal command.

## Use

Agents should follow the deterministic
[agent runbook](references/agent-runbook.md). The short version is to inspect state,
branch once, and verify reuse across separate Playwright CLI processes.

The agent checks the shared session first:

```bash
ai-browser-control-chromeos status
```

If disconnected, the agent starts one durable connection:

```bash
ai-browser-control-chromeos connect
```

This returns immediately with a user-service PID and redacted log path. The agent
asks the user to use only the newest local handoff tab, complete the Chrome
address-bar handoff, then checks or waits:

```bash
ai-browser-control-chromeos status
ai-browser-control-chromeos wait 180
ai-browser-control-chromeos logs 40
```

The user never needs to start, monitor, or stop a terminal process.

`status` uses automation-friendly exit codes: `0` when connected, `2` while the
connection service is waiting, and `1` when disconnected. `wait` returns `124`
on timeout. Connection logs are token-redacted and stored under
`~/.local/state/ai-browser-control-chromeos/`.

After Playwright reports a successful attachment, the supervisor allows time for the
named session to become visible and requires multiple consecutive visibility misses
before declaring a disconnect. This avoids tearing down a healthy relay during the
short registration window immediately after the Chrome handoff.

If a host does not expose a working user service manager, `connect` exits 3 instead
of claiming that a disposable background child started. The agent then starts a
foreground supervisor in one long-lived terminal tool session:

```bash
ai-browser-control-chromeos connect-foreground
```

The agent keeps that tool session alive and uses separate calls for `status`, `wait`,
and browser actions. The user still performs only the Chrome address-bar handoff.
Foreground mode writes the same PID and redacted log files as service mode, so
monitoring and cleanup commands remain unchanged.

If Chrome shows `Missing mcpRelayUrl parameter in URL` or `Failed to connect to MCP
relay: WebSocket error`, that page belongs to a malformed or stopped relay. Do not
retry it. The agent checks status, reconnects once if needed, and tells the user to
use only the newest handoff tab. The handoff helper validates `mcpRelayUrl` before it
opens Chrome.

Then use the browser-control commands:

```bash
ai-browser-control-chromeos verify
ai-browser-control-chromeos goto https://example.com
ai-browser-control-chromeos snapshot
ai-browser-control-chromeos find "Sign in"
ai-browser-control-chromeos click e12
ai-browser-control-chromeos tab-list
```

For a login flow, navigate to the service, let the user log in directly in Chrome,
then continue with `snapshot` or `find`. Never ask for the user's password or copy
authentication secrets out of the page.

## Session behavior

`ai-browser-control-chromeos` uses the `chromeos` session by default. Override it when
separate long-lived browser sessions are useful:

```bash
AI_BROWSER_CONTROL_CHROMEOS_SESSION=research ai-browser-control-chromeos connect
AI_BROWSER_CONTROL_CHROMEOS_SESSION=research ai-browser-control-chromeos snapshot
```

Useful lifecycle commands:

```bash
ai-browser-control-chromeos connect
ai-browser-control-chromeos status
ai-browser-control-chromeos wait 180
ai-browser-control-chromeos logs 40
ai-browser-control-chromeos verify
ai-browser-control-chromeos disconnect
```

`verify` runs both `tab-list` and `snapshot` in fresh Playwright CLI processes and
fails unless both succeed. Agents should use it as the completion gate before
reporting that browser control is ready. Run `status`, `wait`, and `logs` as separate
shell commands because nonzero lifecycle exit codes can represent expected states.

Do not call `connect` before every action. First run `status` and reuse an open or
currently connecting session. `connect` is idempotent: it reports the existing
connection or supervisor rather than starting a duplicate. It also cleans up only
processes belonging to the selected session; it does not globally kill helpers for
other sessions.

Do not replace the wrapper with raw `playwright-cli attach`, `nohup`, or shell `&`.
Those patterns bypass the lifecycle guarantees and can leave Chrome with a stopped
relay address.

## Diagnostics

```bash
./scripts/doctor.sh
```

Validate the repository itself with:

```bash
./scripts/test.sh
```

See [references/troubleshooting.md](references/troubleshooting.md) for common errors,
including `ERR_BLOCKED_BY_CLIENT`, a missing token, and a stale daemon.

## Agent compatibility evidence

A natural-prompt live test on 2026-07-28 passed with OpenCode 1.17.18 and the
configured `nrp/glm-5` model, displayed locally as GLM 5.2. OpenCode independently
loaded the complete skill, ran `status`, reused the connected session without
reconnecting, ran `verify`, and withheld its final success response until both
browser checks passed.

- [GLM 5.2 test report](artifacts/opencode-glm-5.2-2026-07-28/test-report.md)
- [Sanitized transcript and assertions](artifacts/opencode-glm-5.2-2026-07-28/transcript.json)
- [Browser verification screenshot](artifacts/opencode-glm-5.2-2026-07-28/browser-verification.png)

The test covers skill discovery and reuse of an already connected browser session.
The automated suite continues to cover connection lifecycle, reconnect behavior,
redaction, durable supervision, and cross-process verification.

## Security

- The extension token is stored outside the repository with permission mode `600`.
- The wrapper redacts the token if Playwright includes it in terminal output.
- Browser automation has the same access as the signed-in user. Agents should only
  navigate and act within the scope the user authorized.
- Keep the extension and Playwright CLI updated from their official sources.

## Upstream projects

- [Microsoft Playwright CLI](https://github.com/microsoft/playwright-cli)
- [Microsoft Playwright MCP](https://github.com/microsoft/playwright-mcp)
- [Playwright Extension for Chrome](https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm)

## License

MIT
