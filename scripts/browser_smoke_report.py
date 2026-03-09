#!/usr/bin/env python3
"""Summarize and compare persisted browser-agent run artifacts."""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_ROOT = Path.home() / ".agenthub" / "logs" / "browser-agent-runs"


@dataclass
class RunRecord:
    path: Path
    data: dict[str, Any]

    @property
    def created_at(self) -> str:
        return str(self.data.get("createdAt", ""))

    @property
    def outcome(self) -> str:
        return str(self.data.get("outcome", "unknown"))

    @property
    def goal_text(self) -> str:
        return str(self.data.get("goalText", ""))

    @property
    def initial_url(self) -> str:
        return str(self.data.get("initialURL") or "")

    @property
    def final_summary(self) -> str:
        return str(self.data.get("finalSummary", ""))

    @property
    def capture_warnings(self) -> list[str]:
        warnings = self.data.get("captureWarnings") or []
        return [str(value) for value in warnings]

    @property
    def browser_artifacts(self) -> dict[str, Any]:
        value = self.data.get("browserArtifacts") or {}
        return value if isinstance(value, dict) else {}

    @property
    def inspection_history(self) -> list[dict[str, Any]]:
        value = self.data.get("inspectionHistory") or []
        return [item for item in value if isinstance(item, dict)]

    @property
    def recent_history(self) -> list[str]:
        value = self.data.get("recentHistory") or []
        return [str(item) for item in value]

    @property
    def session_id(self) -> str:
        return str(self.data.get("sessionId", ""))

    @property
    def title(self) -> str:
        return self.browser_artifacts.get("state", {}).get("title", "")

    @property
    def url(self) -> str:
        return self.browser_artifacts.get("state", {}).get("urlString", "")

    @property
    def action_trace(self) -> list[dict[str, Any]]:
        value = self.browser_artifacts.get("actionTrace") or []
        return [item for item in value if isinstance(item, dict)]

    @property
    def snapshots(self) -> list[dict[str, Any]]:
        value = self.browser_artifacts.get("snapshots") or []
        return [item for item in value if isinstance(item, dict)]

    @property
    def flow_status(self) -> str:
        return str(self.browser_artifacts.get("flowStatusSummary", ""))

    @property
    def approval_status(self) -> str:
        return str(self.browser_artifacts.get("approvalStatusSummary", ""))

    @property
    def last_stage(self) -> str:
        history = self.inspection_history
        if history:
            return str(history[-1].get("pageStage", "unknown"))
        last_inspection = self.browser_artifacts.get("lastInspection") or {}
        return str(last_inspection.get("pageStage", "unknown"))

    @property
    def boundary_kinds(self) -> list[str]:
        inspection = self.browser_artifacts.get("lastInspection") or {}
        boundaries = inspection.get("transactionalBoundaries") or []
        return [str(item.get("kind", "")) for item in boundaries if isinstance(item, dict)]

    @property
    def semantic_target_count(self) -> int:
        inspection = self.browser_artifacts.get("lastInspection") or {}
        return len(inspection.get("semanticTargets") or [])

    @property
    def action_names(self) -> list[str]:
        return [str(item.get("name", "")) for item in self.action_trace]

    @property
    def scenario_key(self) -> str:
        persisted = str(self.data.get("scenarioCategory") or "")
        if persisted:
            return persisted
        goal = self.goal_text.lower()
        url = self.initial_url.lower()
        if "opentable" in goal or "opentable" in url:
            return "restaurant"
        if "booking.com" in goal or "booking.com" in url or "expedia" in goal or "expedia" in url:
            return "hotel"
        if "google flights" in goal or "google.com/travel/flights" in url or "kayak" in goal or "kayak" in url:
            return "flight"
        if "amazon" in goal or "checkout" in goal or "place order" in goal:
            return "checkout"
        return "other"


def load_records(root: Path) -> list[RunRecord]:
    if root.is_file():
        return [RunRecord(path=root, data=json.loads(root.read_text()))]

    records: list[RunRecord] = []
    for path in sorted(root.rglob("*.json")):
        try:
            data = json.loads(path.read_text())
        except Exception as error:  # noqa: BLE001
            print(f"warning: failed to parse {path}: {error}", file=sys.stderr)
            continue
        if isinstance(data, dict):
            records.append(RunRecord(path=path, data=data))
    return records


def format_record(record: RunRecord) -> str:
    boundary_summary = ", ".join(record.boundary_kinds[:4]) or "none"
    return "\n".join(
        [
            f"- createdAt: {record.created_at}",
            f"  outcome: {record.outcome}",
            f"  scenario: {record.scenario_key}",
            f"  goal: {record.goal_text}",
            f"  url: {record.url or record.initial_url or '-'}",
            f"  stage: {record.last_stage}",
            f"  actions: {len(record.action_trace)}",
            f"  semanticTargets: {record.semantic_target_count}",
            f"  snapshots: {len(record.snapshots)}",
            f"  boundaries: {boundary_summary}",
            f"  flow: {record.flow_status or '-'}",
            f"  approval: {record.approval_status or '-'}",
            f"  summary: {record.final_summary}",
            f"  file: {record.path}",
        ]
    )


def command_summary(args: argparse.Namespace) -> int:
    records = load_records(Path(args.root).expanduser())
    if args.goal:
        needle = args.goal.lower()
        records = [record for record in records if needle in record.goal_text.lower()]
    if args.scenario:
        scenario = args.scenario.lower()
        records = [record for record in records if record.scenario_key == scenario]
    records.sort(key=lambda record: record.created_at, reverse=True)
    if args.limit:
        records = records[: args.limit]

    if not records:
        print("No browser-agent runs matched.")
        return 1

    for record in records:
        print(format_record(record))
    return 0


def command_matrix(args: argparse.Namespace) -> int:
    records = load_records(Path(args.root).expanduser())
    if not records:
        print("No browser-agent runs found.")
        return 1

    latest_by_scenario: dict[str, RunRecord] = {}
    for record in sorted(records, key=lambda item: item.created_at, reverse=True):
        latest_by_scenario.setdefault(record.scenario_key, record)

    print("| Scenario | Outcome | Stage | Actions | Snapshots | Goal | File |")
    print("| --- | --- | --- | ---: | ---: | --- | --- |")
    for scenario in sorted(latest_by_scenario):
        record = latest_by_scenario[scenario]
        print(
            f"| {scenario} | {record.outcome} | {record.last_stage} | "
            f"{len(record.action_trace)} | {len(record.snapshots)} | "
            f"{record.goal_text[:60]} | {record.path.name} |"
        )
    return 0


def command_compare(args: argparse.Namespace) -> int:
    baseline = load_records(Path(args.baseline).expanduser())
    candidate = load_records(Path(args.candidate).expanduser())
    if len(baseline) != 1 or len(candidate) != 1:
        print("compare expects exactly one JSON artifact file for baseline and candidate.", file=sys.stderr)
        return 2

    lhs = baseline[0]
    rhs = candidate[0]

    def compare_line(label: str, left: Any, right: Any) -> None:
        status = "same" if left == right else "changed"
        print(f"- {label}: {status}")
        print(f"  baseline: {left}")
        print(f"  candidate: {right}")

    compare_line("outcome", lhs.outcome, rhs.outcome)
    compare_line("last_stage", lhs.last_stage, rhs.last_stage)
    compare_line("action_count", len(lhs.action_trace), len(rhs.action_trace))
    compare_line("snapshot_count", len(lhs.snapshots), len(rhs.snapshots))
    compare_line("semantic_target_count", lhs.semantic_target_count, rhs.semantic_target_count)
    compare_line("boundary_kinds", lhs.boundary_kinds[:4], rhs.boundary_kinds[:4])
    compare_line("final_summary", lhs.final_summary, rhs.final_summary)
    return 0


def command_scenarios(args: argparse.Namespace) -> int:
    scenario_file = Path(args.file).expanduser()
    scenarios = json.loads(scenario_file.read_text())
    records = load_records(Path(args.root).expanduser())
    if not isinstance(scenarios, list):
        print("Scenario file must be a JSON array.", file=sys.stderr)
        return 2

    latest_by_match: dict[str, RunRecord] = {}
    records_by_time = sorted(records, key=lambda item: item.created_at, reverse=True)
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            continue
        scenario_id = str(scenario.get("id", "unknown"))
        needles = [str(value).lower() for value in scenario.get("matchAny", [])]
        matched = next(
            (
                record
                for record in records_by_time
                if any(
                    needle in record.goal_text.lower() or needle in record.initial_url.lower()
                    for needle in needles
                )
            ),
            None,
        )
        if matched:
            latest_by_match[scenario_id] = matched

    print("| Scenario | Category | Status | Outcome | Stage | Artifact |")
    print("| --- | --- | --- | --- | --- | --- |")
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            continue
        scenario_id = str(scenario.get("id", "unknown"))
        category = str(scenario.get("category", "other"))
        matched = latest_by_match.get(scenario_id)
        if matched is None:
            print(f"| {scenario_id} | {category} | missing | - | - | - |")
            continue
        print(
            f"| {scenario_id} | {category} | found | {matched.outcome} | "
            f"{matched.last_stage} | {matched.path.name} |"
        )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    summary = subparsers.add_parser("summary", help="Summarize recent browser-agent runs.")
    summary.add_argument("--root", default=str(DEFAULT_ROOT))
    summary.add_argument("--goal")
    summary.add_argument("--scenario", choices=["restaurant", "hotel", "flight", "checkout", "other"])
    summary.add_argument("--limit", type=int, default=10)
    summary.set_defaults(func=command_summary)

    matrix = subparsers.add_parser("matrix", help="Show the latest run per scenario category.")
    matrix.add_argument("--root", default=str(DEFAULT_ROOT))
    matrix.set_defaults(func=command_matrix)

    compare = subparsers.add_parser("compare", help="Compare two artifact JSON files.")
    compare.add_argument("--baseline", required=True)
    compare.add_argument("--candidate", required=True)
    compare.set_defaults(func=command_compare)

    scenarios = subparsers.add_parser("scenarios", help="Match latest artifacts against a scenario manifest.")
    scenarios.add_argument("--root", default=str(DEFAULT_ROOT))
    scenarios.add_argument(
        "--file",
        default="docs/browser-live-smoke-scenarios.json",
    )
    scenarios.set_defaults(func=command_scenarios)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
