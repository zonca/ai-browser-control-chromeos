#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cache_dir="$(mktemp -d)"
trap 'rm -rf "$cache_dir"' EXIT

bash -n \
  "$root/bin/playwright-chromeos" \
  "$root/scripts/setup.sh" \
  "$root/scripts/doctor.sh" \
  "$root/scripts/test.sh"

PYTHONPYCACHEPREFIX="$cache_dir" python3 -m py_compile \
  "$root/bin/playwright-chromeos-connect"
python3 -m json.tool "$root/evals/evals.json" >/dev/null

python3 - "$root" <<'PY'
from __future__ import annotations

import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
skill = (root / "SKILL.md").read_text()
if not skill.startswith("---\n"):
    raise SystemExit("SKILL.md is missing YAML frontmatter")
frontmatter = skill.split("---\n", 2)[1]
for field in ("name:", "description:"):
    if field not in frontmatter:
        raise SystemExit(f"SKILL.md frontmatter is missing {field}")

for markdown_file in (root / "README.md", root / "SKILL.md"):
    text = markdown_file.read_text()
    for target in re.findall(r"\[[^]]+\]\(([^)]+)\)", text):
        if "://" in target or target.startswith("#"):
            continue
        path = (markdown_file.parent / target.split("#", 1)[0]).resolve()
        if not path.exists():
            raise SystemExit(f"Broken relative link in {markdown_file.name}: {target}")
PY

"$root/scripts/setup.sh" --help >/dev/null
printf '%s\n' 'All skill checks passed.'
