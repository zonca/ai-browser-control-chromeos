# Troubleshooting

Read this reference only after the normal session-discovery and connection workflow
in `SKILL.md` fails.

## `ai-browser-control-chromeos: command not found`

Run `scripts/doctor.sh`. If the repository is present but the wrappers are missing,
run `scripts/setup.sh` yourself. If `~/.local/bin` is not on `PATH`, invoke the
installed command by absolute path and repair the agent shell's PATH.

## Node.js is missing or too old

Playwright CLI requires Node.js 18 or newer. Ask the user to install a supported
Node.js release inside the Chromebook Linux environment, then rerun setup. Do not
install an unrequested Node version manager or replace the user's existing Node
installation without approval.

## The extension is missing

Linux cannot reliably inspect ChromeOS Chrome's extension list. Ask the user to
confirm that the official Playwright Extension is installed in the ChromeOS browser:

https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm

Do not substitute an unrelated browser-control extension.

## The token is missing

Run `scripts/setup.sh` and let the user enter the token at the hidden prompt. The
default token file is:

```text
~/.config/ai-browser-control-chromeos/extension-token
```

It should have permission mode `600`. Never display its contents.

## `ERR_BLOCKED_BY_CLIENT`

ChromeOS blocks a Crostini application or ordinary web page from directly opening a
`chrome-extension://` address. The agent runs `ai-browser-control-chromeos connect`.
Its localhost page places the generated address on the clipboard after the user
clicks Copy. Ask the user only to paste it into Chrome's address bar and press Enter.

Do not turn the address into a clickable HTTP link; Chrome blocks that path too.

If several old handoff tabs are open, use the newest page titled **Connect AI agent
to Chrome**. A relay URL belongs to one running session and times out after that
session is replaced or stopped.

## A Connect tab appears for every command

The agent is probably launching a new Playwright MCP process or rerunning `attach`
for every action. Use the named CLI wrapper instead:

```bash
ai-browser-control-chromeos status
ai-browser-control-chromeos connect  # agent runs this only when disconnected
ai-browser-control-chromeos goto https://example.com
ai-browser-control-chromeos snapshot
```

The last two commands must be separate invocations that reuse the open session.

## Session reports open but commands fail

First refresh state:

```bash
ai-browser-control-chromeos tab-list
ai-browser-control-chromeos snapshot
```

If the extension connection has actually closed, inspect and reconnect in the
background:

```bash
ai-browser-control-chromeos status
ai-browser-control-chromeos logs 40
ai-browser-control-chromeos disconnect
ai-browser-control-chromeos connect
```

This requires another user handoff because it creates a new relay address.

## Background process remains in `connecting`

Inspect the redacted log and keep the existing supervisor while the user completes
the Chrome handoff:

```bash
ai-browser-control-chromeos status
ai-browser-control-chromeos logs 40
```

If the relay address is stale, restart it yourself:

```bash
ai-browser-control-chromeos disconnect
ai-browser-control-chromeos connect
```

State is stored under `~/.local/state/ai-browser-control-chromeos/`. `connect` is
idempotent and will not create a duplicate while the recorded supervisor is alive.

## Kill only browser-engine daemons

Use this only when a stale daemon cannot detach cleanly:

```bash
playwright-cli kill-all
```

It ends every Playwright CLI session for the current user. It does not close the
external ChromeOS browser, but all extension connections must be re-established.

## The daemon disappears between agent turns

Some agent hosts clean up background children between terminal calls. If a newly
started supervisor disappears immediately, do not repeat the same background
command. Start a foreground persistent supervisor with the agent's terminal tool:

```bash
ai-browser-control-chromeos status
ai-browser-control-chromeos connect-foreground --persistent
```

Allow the terminal tool to yield a live session ID and keep that session open. Run
`status`, `wait`, and browser commands through separate calls. Do not append `&` and
do not ask the user to keep a terminal open. The foreground command registers its
PID, so ordinary status and disconnect commands can see and stop it.

If repeated failed handoffs have left multiple Playwright daemons or stale Connect
tabs, first run:

```bash
ai-browser-control-chromeos disconnect
playwright-cli kill-all
```

Then start exactly one foreground persistent supervisor and use only the newest
handoff page. `kill-all` ends every Playwright CLI session for the current Linux
user, so use it only after targeted reconnect attempts fail.

## Different agents need different session names

Set a stable session name per agent or task:

```bash
AI_BROWSER_CONTROL_CHROMEOS_SESSION=codex ai-browser-control-chromeos connect
AI_BROWSER_CONTROL_CHROMEOS_SESSION=codex ai-browser-control-chromeos snapshot
```

Each new name needs its own initial extension handoff. Prefer the shared default
session when agents are not operating concurrently.

## Generated artifacts appear in a repository

The wrapper sets `PLAYWRIGHT_MCP_OUTPUT_DIR` to a temporary directory by default.
If an existing daemon was started before that setting was installed, detach it and
connect again. Override the directory with `AI_BROWSER_CONTROL_CHROMEOS_OUTPUT_DIR` when
artifacts must be retained.
