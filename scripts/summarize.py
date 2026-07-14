#!/usr/bin/env python3
"""Extract readable feed-post summaries from Playwright output.

Usage:
  ai-browser-control-chromeos snapshot --depth=3 | python3 scripts/summarize.py -
  python3 scripts/summarize.py snapshot.yml
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


POST_MARKER = re.compile(r"Feed post|post by", re.IGNORECASE)
TIME_PATTERN = re.compile(r"(\d+[mhdw] •|Just now •)", re.IGNORECASE)
REACTION_PATTERN = re.compile(r"\b([\d,]+)\s+reactions?\b", re.IGNORECASE)
COMMENT_PATTERN = re.compile(r"\b([\d,]+)\s+comments?\b", re.IGNORECASE)
REPOST_PATTERN = re.compile(r"\b([\d,]+)\s+reposts?\b", re.IGNORECASE)
TEXT_PATTERN = re.compile(r"\b(paragraph|text)[^:]*:\s*(.+?)\s*$", re.IGNORECASE)


def extract_text(line: str) -> tuple[str, str] | None:
    """Return a snapshot text role and its cleaned value."""
    match = TEXT_PATTERN.search(line)
    if not match:
        return None
    role = match.group(1).lower()
    value = match.group(2).strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        value = value[1:-1].strip()
    return role, value


def is_metadata(value: str) -> bool:
    return bool(
        TIME_PATTERN.search(value)
        or REACTION_PATTERN.search(value)
        or COMMENT_PATTERN.search(value)
        or REPOST_PATTERN.search(value)
    )


def finish_post(post: dict[str, Any], posts: list[dict[str, str]]) -> None:
    text_parts = post.pop("text_parts", [])
    unique_parts: list[str] = []
    for part in text_parts:
        if part and part != post.get("author") and part not in unique_parts:
            unique_parts.append(part)
    if unique_parts:
        post["text"] = " ".join(unique_parts)
    if any(post.get(key) for key in ("author", "text", "reactions", "comments", "reposts")):
        posts.append(post)


def parse_snapshot(text: str) -> list[dict[str, str]]:
    """Parse post-like regions from Playwright's YAML-style snapshot text."""
    posts: list[dict[str, str]] = []
    current: dict[str, Any] | None = None

    for line in text.splitlines():
        if POST_MARKER.search(line):
            if current is not None:
                finish_post(current, posts)
            current = {"text_parts": []}
            continue
        if current is None:
            continue

        if time_match := TIME_PATTERN.search(line):
            current["time"] = time_match.group(1)
        if reaction_match := REACTION_PATTERN.search(line):
            current["reactions"] = reaction_match.group(1)
        if comment_match := COMMENT_PATTERN.search(line):
            current["comments"] = comment_match.group(1)
        if repost_match := REPOST_PATTERN.search(line):
            current["reposts"] = repost_match.group(1)

        extracted = extract_text(line)
        if not extracted:
            continue
        role, value = extracted
        if not value or is_metadata(value):
            continue
        if role == "paragraph" and not current.get("author") and len(value) <= 100:
            current["author"] = value
        else:
            current["text_parts"].append(value)

    if current is not None:
        finish_post(current, posts)
    return posts


def format_posts(posts: list[dict[str, Any]]) -> str:
    lines: list[str] = []
    for index, post in enumerate(posts, 1):
        line = f"{index}. {post.get('author') or 'Unknown'}"
        if post.get("time"):
            line += f" ({post['time']})"

        details = [line]
        if post.get("text"):
            details.append(f"   {str(post['text'])[:300]}")

        engagement = []
        for key, label in (
            ("reactions", "reactions"),
            ("comments", "comments"),
            ("reposts", "reposts"),
        ):
            if post.get(key):
                engagement.append(f"{post[key]} {label}")
        if engagement:
            details.append(f"   [{', '.join(engagement)}]")
        lines.append("\n".join(details))

    return "\n\n".join(lines) if lines else "No posts found on the current page."


def summarize_from_eval(page_json: str) -> str:
    """Parse Playwright eval JSON and format its post array."""
    try:
        data = json.loads(page_json)
        if isinstance(data, str):
            data = json.loads(data)
    except json.JSONDecodeError:
        return "Failed to parse page data."

    if isinstance(data, dict):
        data = [data]
    if not isinstance(data, list) or not all(isinstance(post, dict) for post in data):
        return "Failed to parse page data."
    return format_posts(data)


def main() -> None:
    if len(sys.argv) != 2:
        print("Usage: summarize.py <snapshot.yml|->", file=sys.stderr)
        sys.exit(1)

    source = sys.argv[1]
    snapshot = sys.stdin.read() if source == "-" else Path(source).read_text()
    posts = parse_snapshot(snapshot)
    if not posts:
        print("No structured posts found in snapshot.")
        print("Use the documented eval extractor for live feed data.")
        return
    print(format_posts(posts))


if __name__ == "__main__":
    main()
