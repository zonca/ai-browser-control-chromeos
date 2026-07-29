# OpenCode GLM 5.2 browser-control verification

- Date: 2026-07-28
- Result: PASS
- OpenCode: 1.17.18
- Provider: `nrp`
- Model ID: `glm-5`
- Configured display name: GLM 5.2
- Skill commit tested: `9207e76`

## Prompt

> Confirm that you can control my existing ChromeOS Chrome browser. Use the
> relevant installed skill and follow it exactly. Do not ask me to run terminal
> commands. Do not navigate or modify the page. Report the active page title and
> URL only after every required readiness check succeeds.

The prompt intentionally omitted command names. This tested whether the model could
discover the skill and follow its workflow from natural language.

## Observed behavior

1. OpenCode loaded the complete `ai-browser-control-chromeos` skill.
2. GLM 5.2 ran `ai-browser-control-chromeos status` as a separate shell call.
3. It interpreted exit 0 as connected and reused the existing `chromeos` session.
4. It did not call `connect` or `reconnect`.
5. It ran `ai-browser-control-chromeos verify` as a second shell call.
6. `verify` completed `tab-list` and `snapshot` in separate Playwright CLI
   processes.
7. The model waited for verification to pass before reporting the page title and a
   URL with session query parameters removed.
8. It did not navigate, edit the page, expose the relay address, or ask the user to
   run terminal commands.

## Result

All eight assertions passed. The active page was the Playwright extension page
titled `Welcome`. The Chrome extension rendered the cosmetic label `"unknown"
connected.` even though browser control and client-name redaction worked.

See the [sanitized machine-readable transcript](transcript.json) and
[browser screenshot](browser-verification.png).

## Scope

This run verifies skill discovery and warm-session reuse with OpenCode and GLM 5.2.
It does not replace the repository's automated lifecycle tests or claim that every
OpenCode/provider/version combination has been tested.
