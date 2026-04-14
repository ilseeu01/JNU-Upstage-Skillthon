#!/usr/bin/env python3
"""Skill validator for JNU & Upstage Skillthon.

Derived from Anthropic skill-creator quick_validate.py (Apache 2.0):
https://github.com/anthropics/skills/tree/main/skills/skill-creator

Additions for Skillthon:
- Upstage API key usage check
- run() function presence check
- README.md evaluation sections check
- .env security check
"""

import re
import sys
from pathlib import Path

import yaml

ALLOWED_FRONTMATTER_KEYS = {"name", "description", "license", "allowed-tools", "metadata", "compatibility"}

# README sections mapped to evaluation criteria
REQUIRED_README_SECTIONS = [
    ("라이프스타일 문제", "주제 적합성 섹션 (15점)"),
    ("스킬 개요", "창의성 섹션 (30점)"),
    ("기술 스택", "구현 완성도 섹션 (25점)"),
    ("Iteration", "개선 과정 섹션 (구현 완성도 25점)"),
    ("사용 방법", "사용자 편의성 섹션 (20점)"),
    ("확장 계획", "사용 가능성 섹션 (10점)"),
]


def validate_skill(skill_path) -> tuple[bool, str]:
    """Validate a skill directory. Returns (is_valid, message)."""
    skill_path = Path(skill_path)
    errors = []
    warnings = []

    # ── 1. SKILL.md ──────────────────────────────────────────────
    skill_md = skill_path / "SKILL.md"
    if not skill_md.exists():
        return False, "SKILL.md not found"

    content = skill_md.read_text(encoding="utf-8")
    if not content.startswith("---"):
        return False, "No YAML frontmatter found"

    match = re.match(r"^---\n(.*?)\n---", content, re.DOTALL)
    if not match:
        return False, "Invalid frontmatter format"

    try:
        frontmatter = yaml.safe_load(match.group(1))
        if not isinstance(frontmatter, dict):
            return False, "Frontmatter must be a YAML dictionary"
    except yaml.YAMLError as e:
        return False, f"Invalid YAML in frontmatter: {e}"

    unexpected = set(frontmatter.keys()) - ALLOWED_FRONTMATTER_KEYS
    if unexpected:
        errors.append(
            f"Unexpected frontmatter key(s): {', '.join(sorted(unexpected))}. "
            f"Allowed: {', '.join(sorted(ALLOWED_FRONTMATTER_KEYS))}"
        )

    # name
    name = str(frontmatter.get("name", "") or "").strip()
    if not name:
        errors.append("Missing 'name' in frontmatter")
    else:
        if not re.match(r"^[a-z0-9-]+$", name):
            errors.append(f"name '{name}' must be kebab-case (lowercase, digits, hyphens only)")
        if name.startswith("-") or name.endswith("-") or "--" in name:
            errors.append(f"name '{name}' cannot start/end with hyphen or contain consecutive hyphens")
        if len(name) > 64:
            errors.append(f"name is too long ({len(name)} chars, max 64)")
        if name != skill_path.name:
            errors.append(
                f"name '{name}' does not match directory name '{skill_path.name}'"
            )

    # description
    description = str(frontmatter.get("description", "") or "").strip()
    if not description:
        errors.append("Missing 'description' in frontmatter")
    else:
        if "<" in description or ">" in description:
            errors.append("description cannot contain angle brackets (< or >)")
        if len(description) > 1024:
            errors.append(f"description too long ({len(description)} chars, max 1024)")
        if "TODO" in description:
            errors.append("description still contains TODO — fill in WHAT + WHEN before submitting")

    # compatibility (optional)
    compatibility = str(frontmatter.get("compatibility", "") or "").strip()
    if compatibility and len(compatibility) > 500:
        errors.append(f"compatibility too long ({len(compatibility)} chars, max 500)")

    # ── 2. skill/main.py (Skillthon-specific) ────────────────────
    main_py = skill_path / "skill" / "main.py"
    if not main_py.exists():
        errors.append("skill/main.py not found")
    else:
        src = main_py.read_text(encoding="utf-8")
        if "def run(" not in src:
            errors.append("skill/main.py: run() function not found")
        if "UPSTAGE_API_KEY" not in src:
            errors.append(
                "skill/main.py: UPSTAGE_API_KEY not used — "
                "Skillthon requires Upstage API (os.environ.get('UPSTAGE_API_KEY'))"
            )
        if "upstage.ai" not in src:
            errors.append(
                "skill/main.py: Upstage base_url not found — "
                "add base_url='https://api.upstage.ai/v1' to OpenAI client"
            )
        if "TODO" in src:
            warnings.append("skill/main.py: TODO items remain — fill in implementation before submitting")
        if 'if __name__ == "__main__"' not in src:
            warnings.append("skill/main.py: no __main__ block — add a runnable example")

    # ── 3. requirements.txt ───────────────────────────────────────
    req = skill_path / "requirements.txt"
    if not req.exists():
        errors.append("requirements.txt not found")
    elif "openai" not in req.read_text(encoding="utf-8"):
        errors.append("requirements.txt: 'openai' package missing — add openai>=1.0.0")

    # ── 4. README.md (evaluation sections) ───────────────────────
    readme = skill_path / "README.md"
    if not readme.exists():
        errors.append("README.md not found")
    else:
        readme_text = readme.read_text(encoding="utf-8")
        for keyword, label in REQUIRED_README_SECTIONS:
            if keyword not in readme_text:
                errors.append(f"README.md: missing {label} (search keyword: '{keyword}')")
        todo_count = readme_text.count("TODO")
        if todo_count > 3:
            warnings.append(f"README.md: {todo_count} TODO items remain — fill in before submitting")

    # ── 5. Security ───────────────────────────────────────────────
    repo_root = skill_path.parent
    gitignore = repo_root / ".gitignore"
    if not gitignore.exists():
        warnings.append(".gitignore not found in repo root — add one with .env to prevent API key leaks")
    elif ".env" not in gitignore.read_text(encoding="utf-8"):
        warnings.append(".gitignore: .env not listed — API key may be committed accidentally")

    # ── Result ────────────────────────────────────────────────────
    if warnings:
        print("⚠️  Warnings (optional improvements):")
        for w in warnings:
            print(f"   - {w}")
        print()

    if errors:
        return False, "\n".join(f"  - {e}" for e in errors)
    return True, "Skill is valid!"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python skills/solar-skill-creator/scripts/quick_validate.py <skill-name>")
        print("Example: python skills/solar-skill-creator/scripts/quick_validate.py summarize-receipt")
        sys.exit(1)

    repo_root = Path(__file__).resolve().parents[3]
    skill_dir = repo_root / sys.argv[1]

    if not skill_dir.exists():
        print(f"Error: '{skill_dir}' not found")
        sys.exit(1)

    print(f"Validating: {skill_dir.name}\n")
    valid, message = validate_skill(skill_dir)
    print("✅ " + message if valid else "❌ Errors:\n" + message)
    sys.exit(0 if valid else 1)
