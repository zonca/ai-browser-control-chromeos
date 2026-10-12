# Browser runtime maintenance

Preserve the current relay when a health check times out or returns an ambiguous
transport error. Only consecutive explicit responses that the selected session is
not open may end normal supervision or trigger persistent reconnection. Never use
Playwright's registry-pruning `list` command for health checks.

Keep every service and terminal command in the same private Playwright workspace,
independent of the caller's working directory. Test transient errors, hung probes,
recovery without a new attachment, confirmed closure, and cross-directory reuse
with isolated fake sessions before installing a runtime change.

A runtime maintenance test does not require navigating the user's live browser.
Never claim live browser verification from simulated lifecycle checks.

For an explicit unsupported extension protocol error, update the actual Playwright
command-line package and replace only the affected incompatible daemon and handoff.
A wrapper reinstall alone does not update Playwright. Never manually spoof the
protocol version to bypass the extension's compatibility check.
