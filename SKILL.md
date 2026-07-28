---
name: ai-browser-control-chromeos
description: Control the user's existing ChromeOS Chrome browser from an AI coding agent running in Chromebook Crostini, preserving live tabs, cookies, and user-driven logins through one durable Playwright extension connection. Use this whenever the user asks an agent to browse in their current Chromebook Chrome, continue after interactive login, troubleshoot repeated Connect tabs or relay errors, or obtain behavior similar to `claude --chrome`. The agent owns every terminal process and diagnostic; the user only performs Chrome UI handoff, login, MFA, and approval steps.
---

# AI Browser Control for ChromeOS

Connect an agent in Crostini to the user's existing ChromeOS Chrome profile through
the official Playwright extension. Reuse one named session across separate terminal
calls so tabs, cookies, and interactive login state remain available.

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
connection path fails.

## Start every browser task with discovery

Run:

```bash
ai-browser-control-chromeos status
```

Interpret the result:

- Exit 0, `connected`: reuse the session; do not call `connect`.
- Exit 2, `connecting`: keep the existing service and wait; do not open another relay.
- Exit 1, `disconnected`: start one connection.
- Missing command or prerequisite error: run `SKILL_ROOT/scripts/doctor.sh` and fix
  only what it reports.

## Set up a new Chromebook

Ask the user to install the official extension named in README. Then run:

```bash
SKILL_ROOT/scripts/setup.sh
```

The setup stores the token outside the repository with mode `600`. Pause at its
hidden prompt so the user can type the token privately. Do not request the token in
chat. After setup, rerun the doctor and continue with the normal connection path.

## Create one durable connection

Run:

```bash
ai-browser-control-chromeos connect
```

On Crostini this starts a user service, so the Playwright relay survives after the
agent's short terminal call exits. `connect` is idempotent and reports an existing
session or supervisor instead of creating another handoff.

If `connect` exits 3 because durable user services are unavailable, immediately
start this in a long-lived terminal tool call:

```bash
ai-browser-control-chromeos connect-foreground
```

Let the terminal tool yield a live session ID. Keep that tool session open and use
separate calls for status and browser actions. This is a host fallback, not a step
for the user.

When the newest local page titled **Connect AI agent to Chrome** appears, tell the
user:

> In the newest “Connect AI agent to Chrome” tab, click **Copy browser connection
> address**, then press **Ctrl+L**, **Ctrl+V**, and **Enter**. Ignore or close older
> Playwright Connect/error tabs.

Then run:

```bash
ai-browser-control-chromeos wait 180
```

Use `status` periodically instead when the agent runtime needs short responsive
calls. If waiting fails, inspect `ai-browser-control-chromeos logs 40`; logs redact
the extension token.

Verify reuse with two separate commands:

```bash
ai-browser-control-chromeos tab-list
ai-browser-control-chromeos snapshot
```

Success without another Connect page proves the shared session is ready.

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
2. If connected, refresh with `tab-list` and `snapshot`; do not reconnect.
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

Report the final page title and URL without exposing tokens, cookies, or other
secrets.
