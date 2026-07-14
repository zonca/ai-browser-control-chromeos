---
name: playwright-chromeos
description: Control the user's existing ChromeOS Chrome browser from an AI coding agent running in Chromebook Crostini, preserving live tabs, cookies, and user-driven logins through the official Playwright extension and a persistent named CLI session. Use this skill whenever a user asks an agent to browse live in their Chromebook browser, continue after the user logs in, replace repeated Playwright extension Connect tabs, or obtain behavior similar to `claude --chrome` from Codex or another terminal agent.
compatibility: Chromebook Crostini with Bash, Node.js 18+, npm, Python 3, garcon-url-handler, and the official Playwright Chrome extension.
---

# Playwright ChromeOS

Control the user's existing ChromeOS Chrome profile from a terminal-based AI agent.
The workflow uses a named Playwright CLI session so separate shell calls and AI
agents can reuse one extension connection.

## Keep human and agent responsibilities separate

The user installs the Chrome extension, enters its token through a hidden terminal
prompt, completes interactive login, and approves sensitive actions. The agent
diagnoses the environment, runs Playwright commands, observes page state, and
continues after the user confirms the human step.

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

1. Check whether `playwright-chromeos` is available.
2. Run `playwright-chromeos list`.
3. If the `chromeos` session is open, reuse it. Do not run `connect` again.
4. If the command or prerequisites are missing, run `SKILL_ROOT/scripts/doctor.sh`
   and report only the missing items.
5. If the runtime is installed but no session is open, ask the user to start the
   named session once from their normal Linux Terminal and guide the handoff.

Repeated `connect` calls replace the attached session and recreate the Connect tab,
which defeats the purpose of the named daemon.

## Set up a new machine

Do not silently install a Chrome extension or solicit its token in chat. Give the
user the official extension link from README, ask them to install it in ChromeOS
Chrome, and ask them to run this command themselves:

```bash
SKILL_ROOT/scripts/setup.sh
```

Use the actual absolute value of `SKILL_ROOT` in the command you show. The script
permanently installs Playwright CLI, installs the local wrappers, prompts privately
for the token, and installs the skill in the selected agent skill directory.

Ask the user to say when setup is complete, then rerun the doctor and connect. Never
echo, log, summarize, or repeat the token.

## Connect ChromeOS Chrome

Ask the user to run this in the Chromebook's normal Linux Terminal app:

```bash
playwright-chromeos connect
```

The ChromeOS handoff page asks the user to click **Copy Playwright connection
address**. Ask them to click it, then press **Ctrl+L**, **Ctrl+V**, and **Enter** in
Chrome. After the command reports success, verify the shared session:

```bash
playwright-chromeos list
```

The `chromeos` session should be open. Starting it from the user's Terminal keeps
the process independent of AI hosts that remove tool-launched children between
turns. Keep that Terminal app running while agents need browser access.

The token bypasses the extension's approval dialog; it cannot make Crostini directly
open a `chrome-extension://` URL. The copy-and-paste handoff is therefore expected
once per browser/daemon lifetime.

Verify persistence with two separate invocations, for example:

```bash
playwright-chromeos tab-list
playwright-chromeos snapshot
```

If both succeed without another Connect page, the session is ready.

## Operate the browser

Use concise Playwright CLI commands and refs from the latest snapshot:

```bash
playwright-chromeos goto https://example.com
playwright-chromeos snapshot
playwright-chromeos find "Account"
playwright-chromeos click e12
playwright-chromeos fill e19 "text"
playwright-chromeos press Enter
playwright-chromeos tab-list
playwright-chromeos tab-select 1
```

Prefer `find` or a shallow `snapshot --depth=N` before requesting a large snapshot.
After navigation or a meaningful DOM change, refresh the snapshot because refs can
become stale.

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

1. Run `playwright-chromeos list`.
2. If the session is open, retry with a new snapshot rather than reconnecting.
3. If the session is closed, check `SKILL_ROOT/scripts/doctor.sh`.
4. Only then ask the user to rerun `playwright-chromeos connect` in their Terminal
   and perform the one-time handoff.

For `ERR_BLOCKED_BY_CLIENT`, use the local handoff page; do not click or open its
extension URL as a normal HTTP link. For stale or mismatched sessions, follow the
targeted cleanup steps in the troubleshooting reference.

## Finish

Leave the named session open when the user expects more browser work. Detach only
when the user asks to end control or when security requires it:

```bash
playwright-chromeos detach
```

Report the page title and URL that demonstrate the requested outcome, without
including tokens, cookies, or other secrets.
