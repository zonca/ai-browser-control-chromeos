#!/usr/bin/env python3
"""Extract a readable summary of feed posts from a LinkedIn (or similar) page.

Usage:
  ai-browser-control-chromeos snapshot --depth=3 > snapshot.yml
  python3 scripts/summarize.py snapshot.yml

Or pipe the snapshot directly:
  ai-browser-control-chromeos snapshot | python3 scripts/summarize.py -
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def extract_text(obj: dict, depth: int = 0) -> str:
    """Recursively extract text from a snapshot YAML-like dict."""
    if depth > 5:
        return ""
    parts = []
    if isinstance(obj, dict):
        for key, val in obj.items():
            if key == "text":
                parts.append(str(val))
            elif key == "heading":
                parts.append(str(val))
            elif key == "strong":
                parts.append(f"**{val}**")
            elif isinstance(val, (dict, list)):
                parts.append(extract_text(val, depth + 1))
    elif isinstance(obj, list):
        for item in obj:
            parts.append(extract_text(item, depth + 1))
    return " ".join(parts)


def parse_snapshot_yaml(text: str) -> list[dict]:
    """Lightweight parser for playwright-cli snapshot YAML output.

    Returns a list of top-level items.
    """
    # This is a simplified parser - for production use, consider PyYAML
    items = []
    current = {}
    stack = [current]

    for line in text.split("\n"):
        # Skip non-YAML lines
        if not line.strip() or line.strip().startswith("###"):
            continue

        # Calculate indentation
        stripped = line.lstrip()
        indent = len(line) - len(stripped)

        # Pop stack to correct depth
        while len(stack) > 1 and indent <= (len(stack) - 1) * 2:
            stack.pop()

        if stripped.startswith("- "):
            content = stripped[2:]
            if ":" in content:
                key, _, val = content.partition(":")
                child = {key.strip(): val.strip().strip('"')}
                stack[-1].setdefault("items", []).append(child)
                stack.append(child)
            else:
                leaf = {f"_{len(stack[-1].get('items', []))}": content.strip().strip('"')}
                stack[-1].setdefault("items", []).append(leaf)
        elif ":" in stripped:
            key, _, val = stripped.partition(":")
            key = key.strip()
            val = val.strip().strip('"')
            if val:
                stack[-1][key] = val
            else:
                stack[-1][key] = {}
                stack.append(stack[-1][key])

    return items


def summarize_from_eval(page_json: str) -> str:
    """Parse JSON output from playwright eval and extract post summaries."""
    try:
        data = json.loads(page_json)
    except json.JSONDecodeError:
        return "Failed to parse page data."

    if not isinstance(data, list):
        data = [data]

    lines = []
    for i, post in enumerate(data, 1):
        author = post.get("author", "Unknown")
        time = post.get("time", "")
        text = post.get("text", "")[:300]
        reactions = post.get("reactions", "")
        comments = post.get("comments", "")
        reposts = post.get("reposts", "")

        line = f"{i}. {author}"
        if time:
            line += f" ({time})"
        line += "\n"
        if text:
            line += f"   {text}\n"
        engagement = []
        if reactions:
            engagement.append(f"{reactions} reactions")
        if comments:
            engagement.append(f"{comments} comments")
        if reposts:
            engagement.append(f"{reposts} reposts")
        if engagement:
            line += f"   [{', '.join(engagement)}]"
        lines.append(line)

    return "\n".join(lines) if lines else "No posts found on the current page."


def main():
    if len(sys.argv) < 2:
        print("Usage: summarize.py <snapshot.yml|->", file=sys.stderr)
        print("  Or use: ai-browser-control-chromeos eval 'summarizeFeed()' for live extraction", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]
    if path == "-":
        text = sys.stdin.read()
    else:
        text = Path(path).read_text()

    # Try to find post-like content in the snapshot
    # Look for patterns like "author name", timestamps, and engagement
    posts = []
    lines = text.split("\n")
    current_post = {}

    for line in lines:
        # Match author lines (e.g., "Andrea Zonca")
        author_match = re.search(r'paragraph.*?:\s*(.+?)\s*$', line)
        if author_match and not current_post.get("author"):
            candidate = author_match.group(1).strip()
            if len(candidate) < 100 and " " in candidate:
                current_post["author"] = candidate

        # Match timestamps
        time_match = re.search(r"(\d+[hdw] •|Just now •)", line)
        if time_match:
            current_post["time"] = time_match.group(1)

        # Match reaction counts
        reaction_match = re.search(r'"(\d+)\s*reactions?|"(\d+)"', line)
        if reaction_match:
            current_post["reactions"] = reaction_match.group(1) or reaction_match.group(2)

        # Match comment counts
        comment_match = re.search(r'"(\d+)\s*comments?|"(\d+)"', line)
        if comment_match and not current_post.get("reactions"):
            current_post["comments"] = comment_match.group(1) or comment_match.group(2)

        # When we hit a new post marker, save the current one
        if "Feed post" in line or "post by" in line:
            if current_post:
                posts.append(current_post)
            current_post = {}

    if current_post:
        posts.append(current_post)

    if not posts:
        print("No structured posts found in snapshot.")
        print("\nTip: use `ai-browser-control-chromeos eval` to extract live data instead.")
        print("Example:")
        print('  ai-browser-control-chromeos eval \'document.querySelectorAll("article").length\'')
        sys.exit(0)

    for i, post in enumerate(posts, 1):
        author = post.get("author", "Unknown")
        time = post.get("time", "")
        reactions = post.get("reactions", "")
        comments = post.get("comments", "")

        line = f"{i}. {author}"
        if time:
            line += f" ({time})"
        print(line)
        engagement = []
        if reactions:
            engagement.append(f"{reactions} reactions")
        if comments:
            engagement.append(f"{comments} comments")
        if engagement:
            print(f"   [{', '.join(engagement)}]")
        print()


if __name__ == "__main__":
    main()