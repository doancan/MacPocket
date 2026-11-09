#!/bin/bash
# Measures existing behavior in a detached checkout; does not build over the running application.
set -euo pipefail
macpocket_root="$(cd "$(dirname "$0")/.." && pwd)"
macpocket_destination="${1:-$macpocket_root/.build/performance-survey-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$macpocket_destination"
macpocket_destination="$(cd "$macpocket_destination" && pwd -P)"
macpocket_checkout="$macpocket_destination/checkout"
if [[ -e "$macpocket_checkout" ]]; then
    echo 'Choose a new output directory; existing measurements are preserved.' >&2
    exit 2
fi
git -C "$macpocket_root" worktree add --detach "$macpocket_checkout" HEAD
trap 'git -C "$macpocket_root" worktree remove --force "$macpocket_checkout"' EXIT
python3 "$macpocket_root/tools/prepare-performance-survey.py" "$macpocket_root" "$macpocket_checkout"
macpocket_source="$(git -C "$macpocket_checkout" rev-parse HEAD)"
MACPOCKET_SURVEY_SOURCE="$macpocket_source" MACPOCKET_SURVEY_OUTPUT="$macpocket_destination" \
    swift test --package-path "$macpocket_checkout" -c release --filter PerformanceSurveyTests \
    > "$macpocket_destination/run.log" 2>&1
python3 - "$macpocket_destination/report.json" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
required = ['disk', 'search', 'images', 'imagesDetailed', 'sensors', 'ui']
assert all(key in report for key in required), 'An area was not measured'
assert not any(isinstance(value, dict) and 'error' in value for value in report.values()), 'A measurement failed'
assert len(report['disk']) == 4 and len(report['search']) == 16
assert all(row['mainThread'] for row in report['disk'])
assert len(report['ui']['measurements']) == 3
assert all(sum(row['cpuUpdateBodyEvaluations'].values()) > 0 for row in report['ui']['measurements']), 'No view body data'
print(sys.argv[1])
PY
