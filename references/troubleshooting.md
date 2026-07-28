# Troubleshooting

Read this only after the normal discovery and single-connection workflow in
`SKILL.md` fails.

## Command or prerequisite is missing

Run:

```bash
SKILL_ROOT/scripts/doctor.sh
```

The doctor checks Node.js 18+, npm, Python, the ChromeOS URL handler, Playwright CLI,
the installed wrappers, token permissions, and durable user-service support. Repair
only reported failures.

Linux cannot reliably inspect ChromeOS Chrome's extension list. If the runtime is
healthy but Chrome never receives a handoff, ask the user to confirm that the
official Playwright extension from README is installed in ChromeOS Chrome.

If the token is missing, run `scripts/setup.sh` and let the user enter it through the
hidden prompt. Never display the token. Its default file is:

```text
~/.config/ai-browser-control-chromeos/extension-token
```

## Understand status before acting

```bash
ai-browser-control-chromeos status
```

- `connected`: reuse the session and refresh with `tab-list` or `snapshot`.
- `connecting`: keep the existing service and inspect `logs 40`.
- `disconnected`: start one connection.

Repeated `connect` calls do not repair a currently connecting relay and create user
confusion even when the runtime prevents duplicates.

## Bare or stale extension page

Two common Chrome errors are:

```text
Missing mcpRelayUrl parameter in URL
Failed to connect to MCP relay: WebSocket error
```

The first means Chrome opened `connect.html` without the generated relay query
parameter. The second usually means the copied address belongs to a relay process
that has already stopped.

Do not retry the same page or clipboard value. Close or ignore old Playwright
Connect/error tabs, inspect status and logs, then run one targeted reconnect if the
session is disconnected:

```bash
ai-browser-control-chromeos reconnect
```

Use only the newest page titled **Connect AI agent to Chrome**. Click its Copy
button, then paste into Chrome's address bar. The helper now rejects a missing or
invalid `mcpRelayUrl` before opening a handoff page.

## `ERR_BLOCKED_BY_CLIENT`

ChromeOS blocks Crostini applications and ordinary web pages from directly opening
a `chrome-extension://` address. This is expected. Use the localhost handoff page
created by `connect`; do not turn the extension address into an HTTP link or ask the
user to click it.

## Durable service does not start

`connect` uses a transient systemd user service so the relay survives after the
agent's terminal call exits. Inspect it with:

```bash
systemctl --user status "ai-browser-control-chromeos-${UID}-chromeos.service"
ai-browser-control-chromeos logs 80
```

A user manager can report `degraded` and still run transient user services; the
doctor tests the capability directly rather than relying on that summary state.

If `connect` exits 3, start:

```bash
ai-browser-control-chromeos connect-foreground
```

Run it in a long-lived agent terminal tool call and retain the returned session ID.
The user does not run this command.

## Session opens but browser commands fail

First refresh state without reconnecting:

```bash
ai-browser-control-chromeos tab-list
ai-browser-control-chromeos snapshot
```

If status is still connected, use refs from the new snapshot. If status becomes
disconnected, inspect the redacted log and reconnect once.

## Repeated Connect tabs

Check for an agent repeatedly starting `attach`, using different session names, or
retrying a stopped foreground process. Use the shared default session and this
sequence:

```bash
ai-browser-control-chromeos status
ai-browser-control-chromeos connect
ai-browser-control-chromeos wait 180
```

Do not use `--persistent` for an ordinary task. Persistent mode intentionally opens
a new handoff when a real session disconnects and is intended for continuous
monitoring.

The runtime tracks the systemd service, PID, handoff helper, state directory, and
session name together. Cleanup targets only that tuple, so one named session cannot
kill another session's helper.

## Last-resort Playwright daemon cleanup

First use targeted cleanup:

```bash
ai-browser-control-chromeos disconnect
ai-browser-control-chromeos connect
```

Only if Playwright still reports a stale daemon that targeted detach cannot remove,
run:

```bash
playwright-cli kill-all
```

`kill-all` ends every Playwright CLI session for the current Linux user, so it is not
the normal recovery path.

## Different agents need separate sessions

Use a stable safe name:

```bash
AI_BROWSER_CONTROL_CHROMEOS_SESSION=codex ai-browser-control-chromeos connect
AI_BROWSER_CONTROL_CHROMEOS_SESSION=codex ai-browser-control-chromeos snapshot
```

Session names accept 1-64 letters, digits, dots, underscores, and hyphens. Each
session requires its own initial extension handoff. Prefer the shared default unless
agents truly operate concurrently.

## Artifacts appear in a repository

The wrapper sets `PLAYWRIGHT_MCP_OUTPUT_DIR` to a temporary directory. If a daemon
predates that setting, detach and connect again. Set
`AI_BROWSER_CONTROL_CHROMEOS_OUTPUT_DIR` only when artifacts should be retained.
