#!/usr/bin/env python3
"""Validate every tasks/<slug>/task.yaml in the repository.

Checks that each task has the required metadata, a valid 5-field cron
expression and IANA timezone, a non-empty instructions file, a Claude-style
cron string that agrees with cron + timezone, and no duplicate names or task IDs.

Usage: python3 scripts/validate_tasks.py   (exit code 1 on any error)
Requires: PyYAML (pip install pyyaml)
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import yaml

ROOT = Path(__file__).resolve().parent.parent
TASKS = ROOT / "tasks"
REQUIRED = ["name", "slug", "status", "schedule", "instructions_file", "output"]
STATUSES = {"active", "paused", "not_scheduled", "retired"}
SLUG_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
TASK_ID_RE = re.compile(r"^trig_[A-Za-z0-9]+$")
CRON_FIELD_RE = re.compile(r"^[0-9A-Za-z*/,\-?LW#]+$")


def check(path: Path, seen_names: dict, seen_ids: dict) -> list[str]:
    errs: list[str] = []
    rel = path.relative_to(ROOT)
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as e:
        return [f"{rel}: invalid YAML: {e}"]
    if not isinstance(data, dict):
        return [f"{rel}: top level must be a mapping"]

    for key in REQUIRED:
        if key not in data:
            errs.append(f"{rel}: missing required key '{key}'")
    if errs:
        return errs

    slug = data["slug"]
    if not SLUG_RE.match(str(slug)):
        errs.append(f"{rel}: slug '{slug}' must be kebab-case")
    if slug != path.parent.name:
        errs.append(f"{rel}: slug '{slug}' must match folder '{path.parent.name}'")
    if data["status"] not in STATUSES:
        errs.append(f"{rel}: status must be one of {sorted(STATUSES)}")

    task_id = data.get("claude_task_id")
    if task_id is not None and not TASK_ID_RE.match(str(task_id)):
        errs.append(f"{rel}: claude_task_id '{task_id}' does not look like trig_…")
    if data["status"] in {"active", "paused"} and not task_id:
        errs.append(f"{rel}: status '{data['status']}' requires claude_task_id")

    sched = data["schedule"] or {}
    cron, tz = sched.get("cron"), sched.get("timezone")
    if not cron or not tz:
        errs.append(f"{rel}: schedule needs 'cron' and 'timezone'")
    else:
        fields = str(cron).split()
        if len(fields) != 5 or not all(CRON_FIELD_RE.match(f) for f in fields):
            errs.append(f"{rel}: schedule.cron '{cron}' must be 5 cron fields")
        try:
            ZoneInfo(str(tz))
        except (ZoneInfoNotFoundError, ValueError):
            errs.append(f"{rel}: schedule.timezone '{tz}' is not an IANA timezone")
        expected = f"CRON_TZ={tz} {cron}"
        claude_expr = sched.get("claude_cron_expression")
        if claude_expr and claude_expr != expected:
            errs.append(
                f"{rel}: schedule.claude_cron_expression '{claude_expr}' "
                f"disagrees with cron/timezone (expected '{expected}')"
            )

    instr = path.parent / str(data["instructions_file"])
    if not instr.is_file():
        errs.append(f"{rel}: instructions file '{instr.name}' not found")
    elif not instr.read_text(encoding="utf-8").strip():
        errs.append(f"{rel}: instructions file '{instr.name}' is empty")

    out_dir = (data["output"] or {}).get("drafts_dir")
    if out_dir and not (ROOT / out_dir).is_dir():
        errs.append(f"{rel}: output.drafts_dir '{out_dir}' does not exist")

    name = data["name"]
    if name in seen_names:
        errs.append(f"{rel}: duplicate task name '{name}' (also in {seen_names[name]})")
    seen_names[name] = rel
    if task_id:
        if task_id in seen_ids:
            errs.append(f"{rel}: duplicate claude_task_id (also in {seen_ids[task_id]})")
        seen_ids[task_id] = rel
    return errs


def main() -> int:
    files = sorted(TASKS.glob("*/task.yaml"))
    if not files:
        print("validate_tasks: no tasks found under tasks/")
        return 0
    errors: list[str] = []
    seen_names: dict = {}
    seen_ids: dict = {}
    for f in files:
        errors += check(f, seen_names, seen_ids)
    for e in errors:
        print(f"ERROR {e}", file=sys.stderr)
    if errors:
        return 1
    print(f"validate_tasks: {len(files)} task(s) OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
