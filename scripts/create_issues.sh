#!/usr/bin/env bash
# Create labels, milestones, and issues on GitHub from backlog/*.json.
#
# Usage:
#   DRY_RUN=1 scripts/create_issues.sh        # print what would be created, no gh calls
#   scripts/create_issues.sh                   # create on zeketx/sidekick-mechanic
#   REPO=owner/name PROJECT="Sidekick Mechanic" scripts/create_issues.sh
#
# Safe to re-run: labels are upserted, and milestones and issues that already
# exist (matched by exact title) are skipped.
#
# Requires: gh (authenticated with repo scope, plus project scope if PROJECT is set), jq.

set -euo pipefail

REPO="${REPO:-zeketx/sidekick-mechanic}"
PROJECT="${PROJECT:-}"
DRY_RUN="${DRY_RUN:-0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISSUES="$ROOT/backlog/issues.json"
MILESTONES="$ROOT/backlog/milestones.json"

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
if [[ "$DRY_RUN" != "1" ]]; then
  command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
  gh auth status >/dev/null || { echo "run 'gh auth login' first" >&2; exit 1; }
fi

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'DRY RUN:'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

LABELS=(
  "phase:1|1D76DB|Phase 1: chat sidekick, bay map, grounded answers"
  "phase:2|5319E7|Phase 2: live AR, ML, telemetry"
  "phase:3|B60205|Phase 3: garage projector moonshot"
  "area:ios|0E8A16|SwiftUI app and SidekickCore"
  "area:ml|FBCA04|Training, datasets, Core ML"
  "area:telemetry|D93F0B|OBD, BLE, TelemetrySource, simulator"
  "area:rag|0052CC|Backend, retrieval, citations, LLM"
  "area:highlight|C5DEF5|Bay map and highlight rendering"
  "area:docs|BFDADC|Docs, build log, vehicle facts"
  "type:feature|A2EEEF|New user-visible behavior"
  "type:chore|EDEDED|Setup, tooling, maintenance"
  "type:spike|F9D0C4|Time-boxed investigation with a written result"
  "type:bug|D73A4A|Something is broken"
  "size:S|C2E0C6|Under a day"
  "size:M|FEF2C0|One to three days"
  "size:L|F4C7C3|More than three days, consider splitting"
)

echo "== Labels ($REPO)"
for entry in "${LABELS[@]}"; do
  IFS='|' read -r name color desc <<<"$entry"
  run gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force
done

echo "== Milestones"
existing_ms=""
if [[ "$DRY_RUN" != "1" ]]; then
  existing_ms="$(gh api "repos/$REPO/milestones?state=all&per_page=100" --paginate -q '.[].title')"
fi
while IFS= read -r ms; do
  title="$(jq -r '.title' <<<"$ms")"
  desc="$(jq -r '.description' <<<"$ms")"
  if grep -Fxq -- "$title" <<<"$existing_ms"; then
    echo "skip milestone (exists): $title"
    continue
  fi
  run gh api "repos/$REPO/milestones" -X POST -f "title=$title" -f "description=$desc" --silent
done < <(jq -c '.[]' "$MILESTONES")

echo "== Issues"
existing_issues=""
if [[ "$DRY_RUN" != "1" ]]; then
  existing_issues="$(gh issue list --repo "$REPO" --state all --limit 1000 --json title -q '.[].title')"
fi
created=0; skipped=0
while IFS= read -r issue; do
  title="$(jq -r '.title' <<<"$issue")"
  if grep -Fxq -- "$title" <<<"$existing_issues"; then
    echo "skip issue (exists): $title"; skipped=$((skipped + 1))
    continue
  fi
  labels="$(jq -r '.labels | join(",")' <<<"$issue")"
  milestone="$(jq -r '.milestone' <<<"$issue")"
  body_file="$(mktemp)"
  jq -r '.body' <<<"$issue" >"$body_file"
  args=(gh issue create --repo "$REPO" --title "$title" --body-file "$body_file" --label "$labels" --milestone "$milestone")
  [[ -n "$PROJECT" ]] && args+=(--project "$PROJECT")
  run "${args[@]}"
  rm -f "$body_file"
  created=$((created + 1))
done < <(jq -c '.[]' "$ISSUES")

echo "== Done. created=$created skipped=$skipped (dry_run=$DRY_RUN)"
