# Playwright ChromeOS Skill

Use an AI coding agent running inside a Chromebook Linux development environment
(Crostini) to control the user's existing ChromeOS Chrome window. The browser keeps
the user's normal profile, tabs, cookies, and interactive login state.

This repository contains both an agent skill and the small local bridge needed to
make the workflow practical.

## Motivation

`claude --chrome` works well on a Chromebook because Claude Code ships a dedicated
Chrome extension/native-host integration. Codex CLI does not currently provide an
equivalent ChromeOS browser bridge. A normal Chrome DevTools MCP process running in
Crostini sees Linux applications; it cannot simply take over the already-running
ChromeOS browser and its signed-in profile.

The official Playwright extension can connect Playwright to an existing Chrome
window, but a short-lived MCP client may request a new extension connection every
time. On ChromeOS, launching the generated `chrome-extension://.../connect.html`
address from Crostini is also blocked with `ERR_BLOCKED_BY_CLIENT`.

This skill combines:

- Microsoft's official Playwright CLI and Playwright Chrome extension.
- A named Playwright CLI session that separate AI agents can discover and reuse.
- A localhost handoff page for ChromeOS's blocked extension URL.
- A private extension-token file and output redaction.

The result is one user-assisted connection per browser/daemon lifetime, not one
connection per browser action. Microsoft also recommends CLI + skills for coding
agents because it is more token-efficient than loading the full MCP tool schema.

## How it works

```text
AI agent -> playwright-chromeos -> named Playwright CLI daemon
                                      |
                                      v
                              Playwright extension
                                      |
                                      v
                         existing ChromeOS Chrome profile
```

The first `connect` command opens a small local page. The user clicks Copy, pastes
the generated extension address into Chrome's address bar, and presses Enter. Later
commands reuse the named daemon without another Connect tab. A new handoff is needed
after Chrome, the daemon, or the Chromebook is restarted.

## Requirements

- A Chromebook with Linux development environment enabled.
- ChromeOS Chrome, not a separate Linux Chrome profile.
- Node.js 18 or newer and npm inside the Linux environment.
- Python 3 and `garcon-url-handler` inside Crostini.
- The official [Playwright Extension for Chrome](https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm).

The setup script installs `@playwright/cli` globally. It does not use `npx` during
normal operation.

## Installation

```bash
git clone https://github.com/zonca/playwright-chromeos-skill.git
cd playwright-chromeos-skill
./scripts/setup.sh
```

The setup script:

1. Checks Node.js, npm, Python, and the ChromeOS URL handler.
2. Permanently installs `@playwright/cli` if needed.
3. Installs `playwright-chromeos` and its URL handoff helper in `~/.local/bin`.
4. Prompts privately for the extension token and stores it with mode `600`.
5. Links this repository into `~/.agents/skills/playwright-chromeos` by default.

Use another agent skill directory when needed:

```bash
./scripts/setup.sh --skill-dir "$HOME/.claude/skills"
```

Or set `AGENT_SKILLS_DIR` before running setup. Use `--no-skill-install` when only
the browser command should be installed.

### The extension token

Install the Playwright extension, open its connection screen, and copy the token
shown in the `PLAYWRIGHT_MCP_EXTENSION_TOKEN=...` instruction. Run `setup.sh` in
your own terminal and paste the token into its hidden prompt.

Do not paste the token into an AI conversation, issue, log, or repository. For
non-interactive setup, provide it through a trusted secret environment:

```bash
PLAYWRIGHT_MCP_EXTENSION_TOKEN="..." ./scripts/setup.sh
```

## How an agent should ask for prerequisites

An agent can inspect the environment with `scripts/doctor.sh`, but installing the
Chrome extension and entering its token require the user. Keep the request precise
and separate the human actions from the agent's work.

Recommended message:

> Please install the official Playwright Extension in ChromeOS Chrome. Then open
> the extension and copy the token it shows. In the Linux terminal, run
> `./scripts/setup.sh` and paste the token into the hidden prompt. Do not paste the
> token into this chat. Tell me when setup finishes, and I will make the one-time
> browser connection and continue.

If only Node.js or npm is missing, tell the user exactly what the diagnostic found
and ask them to install Node.js 18+ in Crostini. Do not claim the extension is
installed merely because its Web Store page is reachable; Linux cannot reliably
inspect the ChromeOS browser profile.

When the connection page opens, ask:

> Click **Copy Playwright connection address**, then press **Ctrl+L**, **Ctrl+V**,
> and **Enter**. Tell me when the extension page says it is connected.

After that, the agent should verify the named session instead of asking the user to
repeat setup.

## Use

Check the shared session first:

```bash
playwright-chromeos list
```

If it is not open, run this once from the Chromebook's normal Linux Terminal app:

```bash
playwright-chromeos connect
```

Starting it from the user's terminal keeps ownership independent of any one AI
agent. This matters on agent hosts that clean up tool-launched child processes at
the end of a turn. Keep the Terminal app running while browser automation is needed.

Then use normal Playwright CLI commands:

```bash
playwright-chromeos goto https://example.com
playwright-chromeos snapshot
playwright-chromeos find "Sign in"
playwright-chromeos click e12
playwright-chromeos tab-list
```

For a login flow, navigate to the service, let the user log in directly in Chrome,
then continue with `snapshot` or `find`. Never ask for the user's password or copy
authentication secrets out of the page.

## Session behavior

`playwright-chromeos` uses the `chromeos` session by default. Override it when
separate long-lived browser sessions are useful:

```bash
PLAYWRIGHT_CHROMEOS_SESSION=research playwright-chromeos connect
PLAYWRIGHT_CHROMEOS_SESSION=research playwright-chromeos snapshot
```

Useful lifecycle commands:

```bash
playwright-chromeos list
playwright-chromeos detach
playwright-cli kill-all
```

Do not call `connect` before every action. First run `list` and reuse an open
session. A new attach replaces the named session and creates another extension
handoff.

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
