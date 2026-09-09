#!/usr/bin/env bash
# proj-sync: revision 빌드 — SSOT(config.wbs · rtm.data.json) → md(작업)·xlsx(납품). 작업 ⊥ 납품.
#   WBS  : config.wbs → revision/wbs/WBS.md(작업) · deliverables/WBS.xlsx(납품·4시트)
#   RTM  : revision/요구사항추적표/rtm.data.json → *.md(작업) · deliverables/요구사항추적표.xlsx(납품·2시트)
# 멱등·비파괴. 빌드 후 git add·commit·push 는 사용자/PM 판단(매일 commit-push 전제).
# 사용: bash revision_build.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
ps_load_config || exit 1   # PS_ROOT · PS_CONFIG · PS_PY 확보(export 됨)

"$PS_PY" "$HERE/build_wbs_xlsx.py"
"$PS_PY" "$HERE/build_rtm_xlsx.py"
# 회의록(Minutes) — revision/회의록/*.yml 있으면 md(리뷰)+hwpx(납품) 빌드. lxml·PyYAML 필요 → 없으면 비파괴 스킵.
if ls "$PS_ROOT"/revision/회의록/*.yml >/dev/null 2>&1; then
  "$PS_PY" "$HERE/build_minutes.py" || echo "[revision] 회의록 빌드 스킵(lxml·PyYAML 미설치? pip install --user lxml pyyaml)"
fi
# 전제(Premise) — SSOT 있으면 함께 빌드(신선도 재계산). PyYAML 필요 → 없으면 비파괴 스킵.
if [ -f "$PS_ROOT/revision/전제/premise.yml" ]; then
  "$PS_PY" "$HERE/build_premise.py" || echo "[revision] 전제 빌드 스킵(PyYAML 미설치? pip install --user pyyaml)"
fi
echo "[revision] 빌드 완료 → revision/ (다음: git add -A && git commit -m \"revision: $(date +%F)\" && git push)"
