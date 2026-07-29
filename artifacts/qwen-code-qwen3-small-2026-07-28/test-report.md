# Qwen Code browser-control verification

- Date: 2026-07-28
- Result: PASS
- Qwen Code: 0.20.0
- Model: `qwen3-small`
- Skill commit tested: `91fa844`

## Prompt

> Confirm that you can control my existing ChromeOS Chrome browser. Use the
> relevant installed skill and follow it exactly. Do not ask me to run terminal
> commands. Do not navigate or modify the page. Report the active page title and
> URL only after every required readiness check succeeds.

The prompt intentionally omitted command names. This tested whether Qwen Code could
discover the skill and follow its workflow from natural language.

## Observed behavior

1. Qwen Code selected and loaded `ai-browser-control-chromeos`.
2. It ran `ai-browser-control-chromeos status` as a separate shell call.
3. It interpreted exit 0 as connected and reused the existing `chromeos` session.
4. It did not call `connect` or `reconnect`.
5. It ran `ai-browser-control-chromeos verify` as a second shell call.
6. `verify` completed `tab-list` and `snapshot` in separate Playwright CLI
   processes.
7. Qwen waited for verification to pass before reporting the page title and a URL
   with all connection query parameters removed.
8. It did not navigate, edit the page, expose relay details, or ask the user to run
   terminal commands.

## Result

All eight assertions passed. The active page was the Playwright extension page
titled `Welcome`.

See the [sanitized machine-readable transcript](transcript.json) and
[browser screenshot](browser-verification.png).

## Scope

This run verifies skill discovery and warm-session reuse with Qwen Code 0.20.0 and
`qwen3-small`. It does not replace the repository's automated lifecycle tests or
claim that every Qwen Code model and version has been tested.
