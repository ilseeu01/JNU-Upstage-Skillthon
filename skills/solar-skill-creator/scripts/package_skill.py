#!/usr/bin/env python3
"""Package a skill folder into a distributable .skill file.

Derived from Anthropic skill-creator package_skill.py (Apache 2.0):
https://github.com/anthropics/skills/tree/main/skills/skill-creator

Usage:
    python skills/solar-skill-creator/scripts/package_skill.py <skill-name>
    python skills/solar-skill-creator/scripts/package_skill.py summarize-receipt
    python skills/solar-skill-creator/scripts/package_skill.py summarize-receipt ./dist
"""

import fnmatch
import sys
import zipfile
from pathlib import Path

# Import validate from the same package
_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE))
from quick_validate import validate_skill  # noqa: E402

EXCLUDE_DIRS = {"__pycache__", "node_modules", ".git"}
EXCLUDE_GLOBS = {"*.pyc", "*.pyo"}
EXCLUDE_FILES = {".DS_Store", ".env"}          # never package secrets
ROOT_EXCLUDE_DIRS = {"evals"}


def should_exclude(rel_path: Path) -> bool:
    parts = rel_path.parts
    if any(part in EXCLUDE_DIRS for part in parts):
        return True
    if len(parts) > 1 and parts[1] in ROOT_EXCLUDE_DIRS:
        return True
    name = rel_path.name
    if name in EXCLUDE_FILES:
        return True
    return any(fnmatch.fnmatch(name, pat) for pat in EXCLUDE_GLOBS)


def package_skill(skill_path: Path, output_dir: Path | None = None) -> Path | None:
    skill_path = Path(skill_path).resolve()

    if not skill_path.exists() or not skill_path.is_dir():
        print(f"❌ Skill directory not found: {skill_path}")
        return None

    if not (skill_path / "SKILL.md").exists():
        print(f"❌ SKILL.md not found in {skill_path}")
        return None

    print("🔍 Validating skill...")
    valid, message = validate_skill(skill_path)
    if not valid:
        print(f"❌ Validation failed:\n{message}")
        print("   Fix errors above before packaging.")
        return None
    print(f"✅ {message}\n")

    out_dir = Path(output_dir).resolve() if output_dir else Path.cwd()
    out_dir.mkdir(parents=True, exist_ok=True)
    skill_file = out_dir / f"{skill_path.name}.skill"

    try:
        with zipfile.ZipFile(skill_file, "w", zipfile.ZIP_DEFLATED) as zf:
            for file_path in skill_path.rglob("*"):
                if not file_path.is_file():
                    continue
                arcname = file_path.relative_to(skill_path.parent)
                if should_exclude(arcname):
                    print(f"  Skipped : {arcname}")
                    continue
                zf.write(file_path, arcname)
                print(f"  Added   : {arcname}")
        print(f"\n✅ Packaged: {skill_file}")
        return skill_file
    except Exception as e:
        print(f"❌ Packaging failed: {e}")
        return None


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python skills/solar-skill-creator/scripts/package_skill.py <skill-name> [output-dir]")
        sys.exit(1)

    repo_root = Path(__file__).resolve().parents[3]
    skill_path = repo_root / sys.argv[1]
    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else None

    print(f"📦 Packaging: {sys.argv[1]}")
    result = package_skill(skill_path, output_dir)
    sys.exit(0 if result else 1)


if __name__ == "__main__":
    main()
