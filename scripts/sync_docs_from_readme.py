#!/usr/bin/env python3
"""Sync Astro README content from README*.md.

Managed output:
- site/src/generated/readme_sections.json

Managed ranges:
- English: from "## Hardware Setup"
- Chinese: from "## 硬件准备"
"""

from __future__ import annotations

import json
from pathlib import Path

from markdown_it import MarkdownIt


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "site" / "src" / "generated" / "readme_sections.json"


SYNC_JOBS = (
    {
        "locale": "en",
        "readme": ROOT / "README.md",
        "start_heading": "## Hardware Setup",
    },
    {
        "locale": "zh",
        "readme": ROOT / "README_zh.md",
        "start_heading": "## 硬件准备",
    },
)


def _extract_markdown_section(md_text: str, start_heading: str) -> str:
    lines = md_text.splitlines()
    start_idx = -1
    for i, line in enumerate(lines):
        if line.strip() == start_heading:
            start_idx = i
            break
    if start_idx < 0:
        raise ValueError(f"Heading not found: {start_heading}")

    section = "\n".join(lines[start_idx:]).strip() + "\n"
    return section


def _render_markdown_to_html(md_text: str) -> str:
    md = MarkdownIt("commonmark", {"html": False})
    md.enable("table")
    return md.render(md_text).strip()

def sync_once(readme_path: Path, start_heading: str) -> str:
    md_text = readme_path.read_text(encoding="utf-8")
    section_md = _extract_markdown_section(md_text, start_heading)
    return _render_markdown_to_html(section_md)


def main() -> None:
    output_data: dict[str, dict[str, str]] = {}
    for job in SYNC_JOBS:
        output_data[job["locale"]] = {
            "start_heading": job["start_heading"],
            "html": sync_once(
                readme_path=job["readme"],
                start_heading=job["start_heading"],
            ),
        }

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        json.dumps(output_data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Synced README sections into {OUTPUT.relative_to(ROOT)}.")


if __name__ == "__main__":
    main()
