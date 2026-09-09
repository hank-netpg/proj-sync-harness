#!/usr/bin/env bash
# proj-sync: 주간보고(Weekly Report) 빌드 — revision(전제·config.wbs·RTM·history) 증류
#   → reference/management/reports/주간보고_{날짜}.md (발신면: 진행 사항 + 리스크 5섹션 + 맨 위 📮 Slack 발신본).
#   **사실(결정론) 계산만** — 서술·Slack 발신·커밋은 manage-report 스킬(PM)이 이어서 수행(DESIGN §H·A3).
# 의존성: PyYAML(premise.yml). 미설치 시 build_report.py 가 안내.
# 멱등·비파괴. 날짜 고정은 PROJ_SYNC_REPORT_DATE=YYYY-MM-DD (예시·테스트 재현).
# 사용: bash report_build.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
ps_load_config || exit 1   # PS_ROOT · PS_CONFIG · PS_PY 확보(export 됨)

"$PS_PY" "$HERE/build_report.py"
echo "[report] 빌드 완료 (다음: manage-report 스킬 — PM 총평 + slack_post.sh 게시)"
