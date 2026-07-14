# Troubleshooting

Read this reference only after the normal session-discovery and connection workflow
in `SKILL.md` fails.

## `ai-browser-control-chromeos: command not found`

Run `scripts/doctor.sh`. If the repository is present but the wrappers are missing,
ask the user to run `scripts/setup.sh`. If `~/.local/bin` is not on `PATH`, start a
new terminal or add it to the shell's PATH configuration.

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
`chrome-extension://` address. Use `ai-browser-control-chromeos connect`. Its localhost page
places the generated address on the clipboard after the user clicks Copy. The user
must paste it into Chrome's address bar and press Enter.

Do not turn the address into a clickable HTTP link; Chrome blocks that path too.

If several old handoff tabs are open, use the newest page titled **Connect AI agent
to Chrome**. A relay URL belongs to one running session and times out after that
session is replaced or stopped.

## A Connect tab appears for every command

The agent is probably launching a new Playwright MCP process or rerunning `attach`
for every action. Use the named CLI wrapper instead:

```bash
ai-browser-control-chromeos list
ai-browser-control-chromeos connect  # only when no session exists
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

If the extension connection has actually closed, detach and reconnect:

```bash
ai-browser-control-chromeos detach
ai-browser-control-chromeos connect
```

This requires another user handoff because it creates a new relay address.

## Kill only Playwright CLI daemons

Use this only when a stale daemon cannot detach cleanly:

```bash
playwright-cli kill-all
```

It ends every Playwright CLI session for the current user. It does not close the
external ChromeOS browser, but all extension connections must be re-established.

## The daemon disappears between agent turns

Some agent hosts clean up every process started by a tool call, including detached
children. Ask the user to start the session from the Chromebook's normal Linux
Terminal app instead:

```bash
ai-browser-control-chromeos connect
```

After the handoff succeeds, keep the Terminal app running while browser automation
is needed. Other agents can then discover the same named session with
`ai-browser-control-chromeos list`.

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
