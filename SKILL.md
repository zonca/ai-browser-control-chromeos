---
name: ai-browser-control-chromeos
description: Control the user's existing ChromeOS Chrome browser from an AI coding agent running in Chromebook Crostini, preserving live tabs, cookies, and user-driven logins through an agent-managed background connection. Use this skill whenever a user asks an agent to browse live in their Chromebook browser, continue after the user logs in, replace repeated extension Connect tabs, or obtain behavior similar to `claude --chrome` from Codex or another terminal agent. The agent must run and supervise all terminal processes itself; never ask the user to run connection commands.
compatibility: Chromebook Crostini with Bash, Node.js 18+, npm, Python 3, garcon-url-handler, and the official Playwright Chrome extension.
---

# AI Browser Control for ChromeOS

## Quick Start

```bash
ai-browser-control-chromeos status   # check if connected
ai-browser-control-chromeos connect   # start background supervisor
# -> User clicks "Copy browser connection address" in Chrome, then Ctrl+L, Ctrl+V, Enter
ai-browser-control-chromeos status    # verify: "connected: session chromeos is open"
ai-browser-control-chromeos goto https://example.com
ai-browser-control-chromeos snapshot
```

If connection fails: `ai-browser-control-chromeos reconnect` (kills old supervisor, starts fresh).
For continuous supervision: `ai-browser-control-chromeos connect --persistent`
restarts the handoff after a disconnect; the user still completes any Chrome UI step.

Control the user's existing ChromeOS Chrome profile from a terminal-based AI agent.
The workflow uses a named Playwright CLI session so separate shell calls and AI
agents can reuse one extension connection.

## Keep human and agent responsibilities separate

The user installs the Chrome extension, enters its token through a hidden prompt,
completes interactive login, and approves sensitive actions. The agent runs every
terminal command: diagnostics, setup, background connection, polling, browser
control, logs, and cleanup.

This separation keeps credentials out of chat and avoids pretending that Crostini
can directly install or inspect an extension in ChromeOS Chrome.

## Locate this skill

Resolve the directory containing this `SKILL.md` as `SKILL_ROOT`. Run bundled scripts
with absolute paths based on that directory; do not assume the current working
directory is the skill repository.

Read [README.md](README.md) when explaining motivation, installation, or what the
user must do. Read [references/troubleshooting.md](references/troubleshooting.md)
only when connection or command reuse fails.

## Start every browser task with session discovery

1. Check whether `ai-browser-control-chromeos` is available.
2. Run `ai-browser-control-chromeos status`.
3. If connected, reuse the session. If connecting, do not run `connect` again.
4. If the command or prerequisites are missing, run `SKILL_ROOT/scripts/doctor.sh`
   and report only the missing items.
5. If disconnected, run `ai-browser-control-chromeos connect` yourself and guide
   the user through only the Chrome UI handoff.

`connect` is idempotent: it reuses an open session or existing background supervisor
instead of creating another Connect tab.

## Set up a new machine

Do not silently install a Chrome extension or solicit its token in chat. Give the
user the official extension link from README and ask them to install it in ChromeOS
Chrome. Run this command yourself:

```bash
SKILL_ROOT/scripts/setup.sh
```

Use the actual absolute value of `SKILL_ROOT` in the command you show. The script
permanently installs Playwright CLI, installs the local wrappers, prompts privately
for the token, and installs the skill in the selected agent skill directory.

If setup needs the token, pause at the hidden prompt so the user can enter it or ask
them to place it in a trusted secret environment. Never ask for it in chat. After
setup, rerun the doctor and connect yourself.

## Connect ChromeOS Chrome

Start the connection yourself:

```bash
ai-browser-control-chromeos connect
```

`connect` returns immediately after launching a background supervisor (with a 2-second
health check). The ChromeOS handoff page asks the user to click **Copy browser connection
address**. Ask them to click it, then press **Ctrl+L**, **Ctrl+V**, and **Enter** in
Chrome. Do not ask them to use a terminal. Poll while they perform the UI step:

```bash
ai-browser-control-chromeos status
ai-browser-control-chromeos wait 180
```

Use `wait` after telling the user what to click, or poll `status` periodically when
the agent runtime should remain responsive. If connection fails, inspect the
redacted log with `ai-browser-control-chromeos logs 40`.

**Recovery commands:**
- `ai-browser-control-chromeos reconnect` -- kill stale supervisor and start fresh (triggers new handoff)
- `ai-browser-control-chromeos connect --persistent` -- keep restarting the handoff after session drops

The token bypasses the extension's approval dialog; it cannot make Crostini directly
open a `chrome-extension://` URL. The copy-and-paste handoff is therefore expected
once per browser/daemon lifetime.

Verify persistence with two separate invocations, for example:

```bash
ai-browser-control-chromeos tab-list
ai-browser-control-chromeos snapshot
```

If both succeed without another Connect page, the session is ready.

## Operate the browser

Use concise browser-control commands and refs from the latest snapshot:

```bash
ai-browser-control-chromeos goto https://example.com
ai-browser-control-chromeos snapshot
ai-browser-control-chromeos find "Account"
ai-browser-control-chromeos click e12
ai-browser-control-chromeos fill e19 "text"
ai-browser-control-chromeos press Enter
ai-browser-control-chromeos tab-list
ai-browser-control-chromeos tab-select 1
```

Prefer `find` or a shallow `snapshot --depth=N` before requesting a large snapshot.
After navigation or a meaningful DOM change, refresh the snapshot because refs can
become stale.

### Summarize feed posts

For social media feeds (LinkedIn, etc.), extract a readable post summary instead of
parsing the full snapshot:

```bash
ai-browser-control-chromeos eval "$(cat SKILL_ROOT/scripts/summarizeFeed.js)"
```

This returns a JSON array of `{author, time, text, reactions, comments, reposts}`
for up to 20 posts on the current page.

## Hand interactive login to the user

1. Navigate to the login page.
2. Tell the user the browser is ready for them to log in.
3. Stop browser actions while they enter credentials or complete MFA.
4. When the user says they are ready, run `snapshot` and continue in the same
   session.

Never ask the user to send passwords, one-time codes, session cookies, or the
extension token through chat.

## Respect browser authorization

The attached browser may expose personal accounts and authenticated services. Treat
navigation and reading as scoped to the user's request. Obtain whatever approval the
agent's governing instructions require before purchases, messages, deletions,
publishing, account changes, or other consequential writes.

## Recover without unnecessary reconnection

When an action fails:

1. Run `ai-browser-control-chromeos status`.
2. If the session is open, retry with a new snapshot rather than reconnecting.
3. If the session is closed, try `ai-browser-control-chromeos reconnect` (kills stale supervisor, starts fresh).
4. If reconnect fails, check `SKILL_ROOT/scripts/doctor.sh`.
5. If disconnected, run `ai-browser-control-chromeos connect` yourself and ask the
   user only for the Chrome UI handoff.

For `ERR_BLOCKED_BY_CLIENT`, use the local handoff page; do not click or open its
extension URL as a normal HTTP link. For stale or mismatched sessions, follow the
targeted cleanup steps in the troubleshooting reference.

## Finish

Leave the named session open when the user expects more browser work. Detach only
when the user asks to end control or when security requires it:

```bash
ai-browser-control-chromeos disconnect
```

Report the page title and URL that demonstrate the requested outcome, without
including tokens, cookies, or other secrets.
