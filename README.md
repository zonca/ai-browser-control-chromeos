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

The agent runs `connect`, which launches a supervised connection process in the
background and returns immediately. A small local page opens in Chrome. The user
clicks Copy, pastes the generated extension address into Chrome's address bar, and
presses Enter. The agent polls connection status and continues automatically. Later
commands reuse the named daemon without another Connect tab.

## Requirements

- A Chromebook with Linux development environment enabled.
- ChromeOS Chrome, not a separate Linux Chrome profile.
- Node.js 18 or newer and npm inside the Linux environment.
- Python 3 and `garcon-url-handler` inside Crostini.
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

The agent owns all terminal work: diagnostics, installation, setup, background
processes, status polling, browser commands, logs, and cleanup. The user only handles
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

After that, the agent polls the background connection and continues. It must not ask
the user to run a terminal command.

## Use

The agent checks the shared session first:

```bash
ai-browser-control-chromeos status
```

If disconnected, the agent starts the connection in the background:

```bash
ai-browser-control-chromeos connect
```

This returns immediately with a supervisor PID and redacted log path. The agent asks
the user to complete the Chrome address-bar handoff, then checks or waits:

```bash
ai-browser-control-chromeos status
ai-browser-control-chromeos wait 180
ai-browser-control-chromeos logs 40
```

The user never needs to start, monitor, or stop a terminal process.

`status` uses automation-friendly exit codes: `0` when connected, `2` while the
background process is connecting, and `1` when disconnected. `wait` returns `124`
on timeout. Connection logs are token-redacted and stored under
`~/.local/state/ai-browser-control-chromeos/`.

Some agent hosts remove detached child processes after a terminal call finishes. If
the supervisor immediately disappears, the agent starts a foreground supervisor in
a long-lived terminal tool session:

```bash
ai-browser-control-chromeos connect-foreground --persistent
```

The agent keeps that tool session alive and uses separate commands for `status`,
`wait`, and browser actions. The user still performs only the Chrome address-bar
handoff. Foreground mode writes the same PID and redacted log files as background
mode, so monitoring and cleanup commands remain unchanged.

Then use the browser-control commands:

```bash
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
ai-browser-control-chromeos disconnect
```

Do not call `connect` before every action. First run `status` and reuse an open or
currently connecting session. `connect` is idempotent: it reports the existing
connection or supervisor rather than starting a duplicate.

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
