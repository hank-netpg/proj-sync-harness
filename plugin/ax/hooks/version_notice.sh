#!/usr/bin/env bash
# SessionStart 훅 — 사본이 릴리즈보다 낡았으면 세션 시작 때 알린다 (issue #18)
#
# 왜 필요한가:
#   버전 경고는 doctor.sh 에만 있었고, /ax:sync 1단계가 doctor 를 부르므로 **동기화할 때는**
#   잘 보였다. 문제는 명령을 안 돌리면 아무 일도 안 일어난다는 것이다 — slack-pull·revision·
#   minutes 만 쓰는 팀원은 영원히 못 본다. 2026-08-07 의 v0.1.0 사본 init 사고(#14)가 그 형태였다.
#
# 반드시 지킬 것 (이슈가 못박은 3원칙):
#   1. **세션 시작을 막지 않는다.** gh 미인증·오프라인·타임아웃이면 조용히 통과한다.
#      훅이 세션을 느리게 하거나 실패시키면 팀원이 플러그인을 끈다. 그래서 항상 exit 0 이다.
#   2. **하루 1회만 조회한다.** 세션마다 GitHub API 를 때리면 레이트리밋에 걸린다.
#   3. **최신이면 아무 말도 안 한다.** 정상 상태에서 매 세션 배너가 뜨면 사람이 무시하는 법을 배운다.
#
# 알려진 사각지대: gh 미인증 팀원은 여기서도 판정이 되지 않아 낡아도 모른다.
#   비공개 저장소라 비인증 curl 경로를 쓸 수 없다 — 지금은 이 한계를 드러내 두는 것이 최선이다.
#   (doctor.sh 도 같은 조건에서 같은 사각지대를 갖는다.)

# 어떤 실패도 세션을 건드리지 않는다.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# config.sh 는 프로젝트용이라 Python 미발견 경고 등을 낼 수 있다. 훅은 조용해야 하므로 삼킨다.
# (set -e 누수도 여기서 되돌린다 — 훅은 중간에 죽으면 안 된다.)
. "$HERE/../scripts/lib/config.sh" 2>/dev/null || exit 0
. "$HERE/../scripts/lib/version_check.sh" 2>/dev/null || exit 0
set +e

RUN_VER="$(ps_plugin_version 2>/dev/null)"
[ -n "$RUN_VER" ] && [ "$RUN_VER" != "unknown" ] || exit 0

# 하루 1회 — 캐시가 신선하면 API 를 때리지 않는다.
LATEST_VER="$(ps_latest_release_version "${PS_RELEASE_CACHE_TTL:-86400}" 2>/dev/null)"

# 낡았을 때만 말한다. current·ahead·unknown 은 침묵.
[ "$(ps_version_state "$RUN_VER" "$LATEST_VER")" = "outdated" ] || exit 0

ROOT="$(ps_plugin_root 2>/dev/null)"
# 경로가 JSON 을 깨지 않게 최소 이스케이프(백슬래시 → 따옴표 순서를 지킬 것).
ROOT="${ROOT//\\/\\\\}"; ROOT="${ROOT//\"/\\\"}"
printf '{"systemMessage":"⚠️ proj-sync 사본이 낡았습니다: v%s < 최신 v%s\\n   업데이트:  claude plugin update ax@ax-harness\\n   사본: %s"}\n' \
  "$RUN_VER" "$LATEST_VER" "$ROOT"
exit 0
