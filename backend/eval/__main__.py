"""Command line for the eval harness."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from eval.golden import RESULTS_DIR, GoldenSetError
from eval.harness import run_harness
from eval.report import render_job_summary, write_metrics_document
from eval.runner import RunnerError
from spec_guard import SpecGuardUncitedCounter


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run the golden-set eval harness.")
    parser.add_argument(
        "--golden",
        type=Path,
        default=None,
        help="JSONL path. Defaults to golden.jsonl if present, else the fake sample.",
    )
    parser.add_argument(
        "--ci",
        action="store_true",
        help="Score only rows with ci set to true.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=RESULTS_DIR,
        help="Directory for results/<date>.json.",
    )
    parser.add_argument(
        "--date",
        default=None,
        help="UTC date used as the results filename (YYYY-MM-DD).",
    )
    parser.add_argument(
        "--summary-file",
        type=Path,
        default=None,
        help="Append the metrics table to this file (CI job summary).",
    )
    parser.add_argument(
        "--metrics",
        action="store_true",
        help="Regenerate docs/METRICS.md from this run.",
    )
    args = parser.parse_args(argv)
    try:
        payload = run_harness(
            args.golden,
            output_dir=args.output_dir,
            ci_only=args.ci,
            date=args.date,
            uncited_counter=SpecGuardUncitedCounter(),
        )
    except (GoldenSetError, RunnerError) as exc:
        print(f"eval failed: {exc}", file=sys.stderr)
        return 1
    results_path = args.output_dir / f"{payload['date']}.json"
    summary = render_job_summary(payload)
    print(summary, end="")
    print(f"Wrote {results_path}")
    if args.summary_file is not None:
        _append_summary(args.summary_file, summary)
    if args.metrics:
        destination = write_metrics_document(results_path)
        print(f"Wrote {destination}")
    return 0


def _append_summary(path: Path, summary: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        if handle.tell() > 0:
            handle.write("\n")
        handle.write(summary)


if __name__ == "__main__":
    raise SystemExit(main())
