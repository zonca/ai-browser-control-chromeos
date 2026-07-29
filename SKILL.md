---
name: ai-browser-control-chromeos
description: Control the user's existing ChromeOS Chrome browser from an AI coding agent running in Chromebook Crostini, preserving live tabs, cookies, and user-driven logins through one durable Playwright extension connection. Use this whenever the user asks an agent to browse in their current Chromebook Chrome, continue after interactive login, troubleshoot repeated Connect tabs or relay errors, or obtain behavior similar to `claude --chrome`. The agent owns every terminal process and diagnostic; the user only performs Chrome UI handoff, login, MFA, and approval steps.
---

# AI Browser Control for ChromeOS

Connect an agent in Crostini to the user's existing ChromeOS Chrome profile through
the official Playwright extension. Reuse one named session across separate terminal
calls so tabs, cookies, and interactive login state remain available.

## Completion gate

Do not report that browser control is ready or finish a browser-control test until
`ai-browser-control-chromeos verify` exits 0. A successful `status`, `wait`, or
`tab-list` alone is not completion. Run lifecycle and diagnostic commands
separately; never join `status` to another command with `&&` or `||`, because its
nonzero exit codes can describe expected states.

## Keep responsibilities clear

The agent runs diagnostics, setup, connection services, polling, logs, browser
commands, and cleanup. The user installs the Chrome extension, enters its token
through a hidden local prompt, completes the Chrome address-bar handoff, logs in,
and approves consequential actions.

Never ask the user to run terminal commands or paste passwords, MFA codes, cookies,
or the extension token into chat.

## Locate the runtime

Resolve the directory containing this file as `SKILL_ROOT`. Run bundled scripts by
absolute path because the user's working directory may be an unrelated repository.

Read [README.md](README.md) for installation or architecture questions. Read
[references/troubleshooting.md](references/troubleshooting.md) only after the normal
connection path fails. Read
[references/agent-runbook.md](references/agent-runbook.md) when exact command exit
codes, environment settings, or recovery branches are needed.

## Follow this connection algorithm

Use the same session name for every command in one browser-control task. The default
is `chromeos`; do not set an environment override unless isolation is genuinely
needed.

1. Run discovery before any setup or connection command:

```bash
ai-browser-control-chromeos status
```

2. Branch on the status exit code:

- Exit 0, `connected`: reuse the session; do not call `connect`.
- Exit 2, `connecting`: keep the existing supervisor and run `wait 180`; do not call
  `connect` or open another relay.
- Exit 1, `disconnected`: start one connection.
- Missing command or prerequisite error: run `SKILL_ROOT/scripts/doctor.sh` and fix
  only what it reports.

3. Only when disconnected, run:

```bash
ai-browser-control-chromeos connect
```

Treat its exit codes as a contract:

- Exit 0: a durable service started or an existing session/supervisor was reused.
- Exit 3: the host cannot provide background supervision. Start
  `connect-foreground` in one long-lived terminal tool session, retain that tool's
  session ID, and keep it alive while other tool calls run.
- Any other nonzero exit: inspect `logs 40`, then run the doctor. Do not hide the
  failure with shell backgrounding.

The exact foreground fallback command is:

```bash
ai-browser-control-chromeos connect-foreground
```

4. If a new handoff page opens, give the Chrome instruction below exactly once.
5. Run `wait 180`.
6. Run the deterministic verification:

```bash
ai-browser-control-chromeos verify
```

`verify` launches `tab-list` and `snapshot` in separate Playwright CLI processes.
Both must succeed without another Connect page. This check proves that later agent
calls can reuse the durable session.

Do not invoke raw `playwright-cli attach`, append `&`, use `nohup`, or repeatedly
call `connect`. Those patterns bypass supervision or create stale handoffs.

## Set up a new Chromebook

Ask the user to install the official extension named in README. Then run:

```bash
SKILL_ROOT/scripts/setup.sh
```

The setup stores the token outside the repository with mode `600`. Pause at its
hidden prompt so the user can type the token privately. Do not request the token in
chat. After setup, rerun the doctor and return to the connection algorithm.

## Complete the Chrome handoff

When the newest local page titled **Connect AI agent to Chrome** appears, tell the
user:

> In the newest “Connect AI agent to Chrome” tab, click **Copy browser connection
> address**, then press **Ctrl+L**, **Ctrl+V**, and **Enter**. Ignore or close older
> Playwright Connect/error tabs.

Then run:

```bash
ai-browser-control-chromeos wait 180
```

`wait` exits 0 when connected, 1 if the supervisor stops, 2 for invalid input, and
124 on timeout. Use `status` periodically instead when the agent runtime needs short
responsive calls. On failure, inspect `ai-browser-control-chromeos logs 40`; logs
redact the extension token. Return to the status branch instead of blindly creating
another relay. A timeout is not completion: if `status` still says `connecting`,
keep the same supervisor, repeat the handoff instruction if needed, and wait again.

## Do not retry stale relay pages

These Chrome messages identify an old or malformed handoff:

- `Missing mcpRelayUrl parameter in URL`
- `Failed to connect to MCP relay: WebSocket error`

Do not ask the user to retry that page or reuse the clipboard value. Close or ignore
the stale page, run `status`, and inspect logs. If disconnected, run:

```bash
ai-browser-control-chromeos reconnect
```

Ask the user to use only the single newest handoff tab. The runtime validates
`mcpRelayUrl` before opening Chrome, so a newly generated bare extension URL fails
locally rather than wasting a browser attempt.

## Operate the browser

Use refs from the latest snapshot:

```bash
ai-browser-control-chromeos goto https://example.com
ai-browser-control-chromeos snapshot --depth=3
ai-browser-control-chromeos find "Account"
ai-browser-control-chromeos click e12
ai-browser-control-chromeos fill e19 "text"
ai-browser-control-chromeos press Enter
ai-browser-control-chromeos tab-list
ai-browser-control-chromeos tab-select 1
```

Prefer `find` or a shallow snapshot before requesting a large page tree. Refresh the
snapshot after navigation or a meaningful DOM change because element refs can become
stale.

For social feeds, use the bundled extractor instead of parsing a full snapshot:

```bash
ai-browser-control-chromeos eval "$(cat SKILL_ROOT/scripts/summarizeFeed.js)"
```

## Hand interactive login to the user

Navigate to the login page, tell the user Chrome is ready, and pause browser actions.
After the user confirms login or MFA is complete, run a new snapshot and continue in
the same session.

## Recover by state, not by repeated attempts

1. Run `status`.
2. If connected, run `verify`; do not reconnect.
3. If connecting, keep the existing supervisor and inspect its redacted log.
4. If disconnected, run `reconnect` once and use only the newest handoff.
5. If durable service startup exits 3, use one foreground terminal session.
6. Run `doctor.sh` if the new supervisor exits or prerequisites may have changed.
7. Use the targeted cleanup in the troubleshooting reference only when these checks
   show stale processes.

Use `connect --persistent` only for explicitly continuous monitoring. It recreates a
handoff after a real session disconnect, which is undesirable for ordinary tasks.

## Authorization and finish

The attached browser has the user's signed-in access. Stay within the requested
scope and obtain whatever approval the governing instructions require before
purchases, messages, deletions, publishing, account changes, or other consequential
writes.

Leave the session open when more browser work is expected. Otherwise run:

```bash
ai-browser-control-chromeos disconnect
```

Before the final response, confirm that `verify` exited 0. If it did not, report the
current state and required user handoff instead of claiming success.

Report the final page title and URL without exposing tokens, cookies, or other
secrets.
