# Live ChromeOS connection test, 2026-10-12

The installed Playwright command-line tool was version 0.1.22. The updated wrapper
and background supervisor used the existing ChromeOS extension connection.

## Results

- Completed 12 form cycles in a temporary tab: 24 input fills and 12 button clicks,
  with an assertion of the resulting values after every cycle.
- Alternated commands between `/tmp` and an unrelated repository directory.
- Captured four fresh snapshots during the form exercise.
- Completed a browser command that remained in progress for 35 seconds while
  background health monitoring continued.
- Passed the wrapper's cross-process tab-list and snapshot verification.
- Retained the same active supervisor throughout the 108.6-second exercise.
- Observed no inconclusive health checks, closure responses, supervisor restarts,
  or additional attachments in the connection log during the exercise.

The first attempt to navigate the temporary tab to a data URL returned
`net::ERR_ABORTED`. The connection survived. The test instead installed its local
form content in that same blank tab through Playwright. No external form was
submitted and no existing user page was changed.

Closed the temporary test tab and passed live tab-list and snapshot verification
again after cleanup. Left the browser-control connection open.

## Scope

These results demonstrate live form operations, working-directory independence,
and stability during a long browser command. This exercise did not deliberately
interrupt the live transport or produce a health-probe timeout. Recovery from
those failures remains covered by the isolated lifecycle regression tests.
