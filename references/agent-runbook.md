# Agent Runbook

Use this reference when an AI agent needs the exact operational contract for the
ChromeOS browser bridge. The normal path remains in `SKILL.md`.

## Invariants

- The agent owns every terminal process, diagnostic, wait, log inspection, and
  cleanup operation.
- The user only installs the Chrome extension, types the token into a hidden local
  prompt, completes the Chrome address-bar handoff, performs login or MFA, and
  approves consequential actions.
- One task uses one stable session name across every command. The default is
  `chromeos`.
- A normal `connect` call returns after a transient systemd user service owns the
  relay. The relay must not remain a child of the short-lived agent shell.
- `connect-foreground` is the only fallback when `connect` exits 3. The agent keeps
  that terminal tool session alive.

Never substitute raw `playwright-cli attach`, `nohup`, shell `&`, repeated
`connect` calls, or user-run terminal commands for this lifecycle.

Do not combine lifecycle commands with `&&` or `||`. In particular, `status` exit 2
means `connecting`, so boolean chaining can incorrectly skip the required next
diagnostic.

## Deterministic start sequence

Run each command in a separate agent terminal invocation unless foreground fallback
is explicitly required.

```bash
ai-browser-control-chromeos status
```

| Result | Meaning | Required next action |
|---|---|---|
| Exit 0, `connected` | Named browser session is open | Run `verify` and reuse it |
| Exit 2, `connecting` | A supervisor is already waiting | Run `wait 180`; do not call `connect` |
| Exit 1, `disconnected` | No session or supervisor exists | Run one `connect` |
| Other failure | Runtime or prerequisite problem | Run `SKILL_ROOT/scripts/doctor.sh` |

When status is disconnected:

```bash
ai-browser-control-chromeos connect
```

| Exit | Meaning | Required next action |
|---|---|---|
| 0 | Service started, or existing connection was reused | If a handoff page opened, instruct the user once; then wait |
| 3 | Durable user service is unavailable | Start `connect-foreground` in one long-lived agent terminal call |
| Other nonzero | Startup failed | Inspect `logs 40`, run the doctor, and report the concrete failure |

Exit 3 from `connect` requires this exact foreground fallback:

```bash
ai-browser-control-chromeos connect-foreground
```

Retain the terminal tool's live session ID. Run status, wait, and browser commands in
other terminal invocations. Do not wait for this foreground command to finish
before continuing, because its job is to remain alive.

## Exact user handoff

Only when a new page titled **Connect AI agent to Chrome** opens, say:

> In the newest “Connect AI agent to Chrome” tab, click **Copy browser connection
> address**, then press **Ctrl+L**, **Ctrl+V**, and **Enter**. Ignore or close older
> Playwright Connect/error tabs.

Do not ask the user to run commands, copy diagnostic output into chat, or keep trying
old Connect tabs.

Then run:

```bash
ai-browser-control-chromeos wait 180
```

| Exit | Meaning | Required next action |
|---|---|---|
| 0 | Session is visible | Run `verify` |
| 1 | Supervisor stopped before connection | Read `logs 40`, rerun `status`, and connect once only if now disconnected |
| 2 | Invalid wait argument | Correct the agent's command |
| 124 | Timed out while supervisor remained active | Read status and logs; keep the existing supervisor if status is `connecting` |

Exit 124 does not prove that the relay is broken. Check status and preserve a
supervisor that is still `connecting`.

Exit 1 can also follow the final health checks of a session that was previously
connected. Run the doctor only when the log shows a startup, dependency, or service
failure; a normal sequence of consecutive session-visibility misses requires a new
connection, not dependency repair.

## Cross-process verification

Run:

```bash
ai-browser-control-chromeos verify
```

The command launches `tab-list` and `snapshot` in fresh Playwright CLI processes.
Success without a new handoff proves the durable session works across process
boundaries. A successful `status`, `wait`, or `tab-list` alone is not final
verification. Do not claim completion until `verify` exits 0.

If either verification command fails:

1. Run `status`.
2. If connected, retry only the failed browser command with a fresh snapshot.
3. If connecting, inspect `logs 40` and wait on the existing supervisor.
4. If disconnected, run `reconnect` once and use only the newest handoff page.

## Stale relay errors

These Chrome errors describe a bad page, not an instruction to retry:

```text
Missing mcpRelayUrl parameter in URL
Failed to connect to MCP relay: WebSocket error
```

Ignore or close the old page and discard its copied address. Run `status`. Reconnect
only when status exits 1. If status exits 2, do not retry any page: wait on the
current supervisor, then rerun status if that wait fails. Start one fresh connection
only after status reports `disconnected`.

## Session naming

Use the default shared session unless concurrent independent browser work requires
isolation. If a custom name is necessary, provide the same environment setting on
every command:

```bash
AI_BROWSER_CONTROL_CHROMEOS_SESSION=research ai-browser-control-chromeos status
AI_BROWSER_CONTROL_CHROMEOS_SESSION=research ai-browser-control-chromeos connect
AI_BROWSER_CONTROL_CHROMEOS_SESSION=research ai-browser-control-chromeos wait 180
AI_BROWSER_CONTROL_CHROMEOS_SESSION=research ai-browser-control-chromeos snapshot
```

Valid names contain 1 to 64 letters, digits, dots, underscores, or hyphens and start
with a letter or digit.

## Command contract

| Command | Purpose | Important behavior |
|---|---|---|
| `status` | Inspect session state | Exit 0 connected, 2 connecting, 1 disconnected |
| `connect` | Start or reuse durable supervision | Idempotent; exit 3 requests foreground fallback |
| `connect-foreground` | Run supervision in a retained terminal | Agent-only fallback |
| `wait [seconds]` | Poll for connection | Default 180 seconds; exit 124 on timeout |
| `logs [lines]` | Read token-redacted connection logs | Default 40 lines |
| `reconnect` | Targeted stop and start | Use once, only after state proves disconnection |
| `disconnect` | Stop only the selected named session | Do not use while follow-up browser work is expected |
| Any other command | Pass through to Playwright CLI | Uses the selected named session |

`connect --persistent` is reserved for explicit continuous monitoring. It
intentionally starts a fresh handoff after a real disconnect and should not be used
for ordinary browser tasks.

## Configuration

Most agents need no overrides. These variables are useful for controlled testing or
advanced isolation:

| Variable | Default | Purpose |
|---|---|---|
| `AI_BROWSER_CONTROL_CHROMEOS_SESSION` | `chromeos` | Stable named session |
| `AI_BROWSER_CONTROL_CHROMEOS_CLIENT_NAME` | `AI Browser Control` | Label sent to the extension UI |
| `AI_BROWSER_CONTROL_CHROMEOS_TOKEN_FILE` | `~/.config/ai-browser-control-chromeos/extension-token` | Secret token file |
| `AI_BROWSER_CONTROL_CHROMEOS_STATE_DIR` | `~/.local/state/ai-browser-control-chromeos` | PID and redacted log state |
| `AI_BROWSER_CONTROL_CHROMEOS_OUTPUT_DIR` | `/tmp/ai-browser-control-chromeos-$UID` | Playwright artifacts |
| `AI_BROWSER_CONTROL_CHROMEOS_SUPERVISOR` | `auto` | `auto`, `systemd`, or `foreground` |
| `AI_BROWSER_CONTROL_CHROMEOS_ATTACH_READY_TIMEOUT` | `10` | Seconds allowed for initial session registration |
| `AI_BROWSER_CONTROL_CHROMEOS_DISCONNECT_MISSES` | `3` | Consecutive missing-session checks before exit |
| `AI_BROWSER_CONTROL_CHROMEOS_POLL_INTERVAL` | `15` | Seconds between health checks |

Do not change readiness or health-check timing to mask a failure. Inspect the
redacted log and fix the observed cause.

## Completion

Leave the session open when more browser work is likely. Otherwise run:

```bash
ai-browser-control-chromeos disconnect
```

Report the final page title and URL, any requested task result, and whether the
session remains connected. Never report extension tokens, cookies, passwords, or
MFA values.
