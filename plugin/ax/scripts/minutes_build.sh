#!/usr/bin/env bash
# proj-sync: 회의록(Minutes) 빌드 — revision/회의록/*.yml(SSOT) → md(리뷰·revision)+hwpx(납품·deliverables).
#   양식 HWPX 를 스켈레톤(reference/form/회의록-양식.hwpx) 주입으로 생성(서식 보존). 회의별 날짜별 시리즈.
# 의존성: lxml·PyYAML (build_minutes.py/엔진이 사용). 미설치 시 엔진이 안내.
# 멱등·비파괴. 빌드 후 git add·commit 은 사용자/PM 판단(revision 축 commit 리듬).
# 사용: bash minutes_build.sh [특정.yml]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
ps_load_config || exit 1   # PS_ROOT · PS_CONFIG · PS_PY 확보(export 됨)

if ! ls "$PS_ROOT"/revision/회의록/*.yml >/dev/null 2>&1; then
  echo "[회의록] revision/회의록/*.yml 없음 — 회의별 yml 을 먼저 두세요(manage-minutes 스킬)." >&2
  exit 0
fi
"$PS_PY" "$HERE/build_minutes.py" "$@"
echo "[회의록] 빌드 완료 → revision/회의록/*.md + deliverables/회의록/*.hwpx (다음: git add -A && git commit -m \"revision: 회의록 $(date +%F)\")"
