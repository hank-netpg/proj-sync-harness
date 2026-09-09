#!/usr/bin/env bash
# proj-sync: 전제(Premise) 빌드 — revision/전제/premise.yml(SSOT) → 최상위 PREMISE.md(리뷰·신선도).
#   운영시점 사업 전제 레지스터. revision 4항목(history·WBS·RTM·회의록)을 증류한 것 — 매주 갱신 권장.
#   신선도: 각 전제 근거가 확인시점 이후 git 갱신되면 '재확인 필요' 자동 표기(결정론).
# 의존성: PyYAML (revision 도구 첫 비-stdlib 예외). 미설치 시 build_premise.py 가 안내.
# 멱등·비파괴. 빌드 후 git add·commit 은 사용자/PM 판단(revision 축 commit 리듬).
# 사용: bash premise_build.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
ps_load_config || exit 1   # PS_ROOT · PS_CONFIG · PS_PY 확보(export 됨)

if [ ! -f "$PS_ROOT/revision/전제/premise.yml" ]; then
  echo "[premise] revision/전제/premise.yml 없음 — manage-premise 스킬로 전제를 먼저 증류하세요." >&2
  exit 0
fi
"$PS_PY" "$HERE/build_premise.py"
echo "[premise] 빌드 완료 → PREMISE.md (다음: git add -A && git commit -m \"revision: premise $(date +%F)\")"
