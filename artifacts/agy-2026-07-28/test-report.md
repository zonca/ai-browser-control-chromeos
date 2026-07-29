# Agy browser-control verification

- Date: 2026-07-28
- Result: PASS after one skill improvement
- Agy: 1.1.8
- Model selection: Agy-managed default
- Skill commit tested: `91fa844`

## Prompt

> Confirm that you can control my existing ChromeOS Chrome browser. Use the
> relevant installed skill and follow it exactly. Do not ask me to run terminal
> commands. Do not navigate or modify the page. Report the active page title and
> URL only after every required readiness check succeeds.

The prompt intentionally omitted command names. This tested whether Agy could
discover the skill and follow its workflow from natural language.

## Improvement found during testing

The first run correctly discovered the skill, reused the session, and passed
verification, but its final response retained the connection URL's query string
after token redaction. That query still contained a local port and relay identifier.

Commit `91fa844` clarified that an agent must remove the entire query string and
fragment from a `chrome-extension://` connection URL. A fresh Agy conversation then
loaded the revised skill and passed every assertion.

## Final observed behavior

1. Agy loaded the complete `ai-browser-control-chromeos` skill.
2. It ran `ai-browser-control-chromeos status` as a separate shell call.
3. It interpreted exit 0 as connected and reused the existing `chromeos` session.
4. It did not call `connect` or `reconnect`.
5. It ran `ai-browser-control-chromeos verify` as a second shell call.
6. `verify` completed `tab-list` and `snapshot` in separate Playwright CLI
   processes.
7. Agy waited for verification to pass before reporting the title and correctly
   stripped every connection query parameter from the URL.
8. It did not navigate, edit the page, expose relay details, or ask the user to run
   terminal commands.

## Result

All eight assertions passed on the revised skill. The active page was the
Playwright extension page titled `Welcome`.

See the [sanitized machine-readable transcript](transcript.json) and
[browser screenshot](browser-verification.png).

## Scope

This run verifies skill discovery and warm-session reuse with Agy 1.1.8 and its
managed default model. It does not replace the repository's automated lifecycle
tests or claim that every Agy model and version has been tested.
