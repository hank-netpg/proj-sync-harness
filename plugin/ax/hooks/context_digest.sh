#!/usr/bin/env bash
# SessionStart 훅 — 직전까지의 결정·미해결·일정을 세션에 주입한다 (세션 연속성)
#
# 왜 필요한가:
#   팀원이 **각자의 Claude 계정**으로 **서로 다른 머신**에서 같은 사업 저장소를 작업한다.
#   git 은 동기화되지만 Claude Code 의 맥락은 이어지지 않아, 새 세션은 매번 백지에서 시작하고
#   무엇이 결정됐고 무엇이 미해결인지 사람이 다시 설명해야 했다.
#
#   세션 기록(transcript) 자체를 공유하는 길은 없다 — 저장 경로가 `~/.claude/projects/
#   -Users-<계정>-<경로>/` 라 머신마다 슬러그가 다르고, 계정 uuid 가 박히며, 세션당 1~12MB 다.
#   이어져야 할 것은 대화 원문이 아니라 **결정·미해결·일정**이고, 그것은 이미 저장소에 있다
#   (revision/history.md · premise.yml · config.wbs — 21개 사업 전부 보유).
#   이 훅은 그것을 **읽히게** 만든다.
#
# 반드시 지킬 것 (version_notice.sh 가 못박은 3원칙 + 2):
#   1. **세션 시작을 막지 않는다.** 무슨 일이 있어도 exit 0. 훅이 세션을 죽이면 팀원이 플러그인을 끈다.
#   2. **네트워크를 타지 않는다.** 전부 로컬 파일 + git log. 세션마다 도는 훅이라 API 를 때리면 안 된다.
#   3. **말할 게 없으면 침묵한다.** 빈 머리글만 매 세션 뜨면 사람이 무시하는 법을 배운다.
#   4. **상한을 지킨다.** 주입분은 매 세션 컨텍스트를 차지한다(build_report.py DIGEST_CAP).
#   5. **판정을 복제하지 않는다.** 지연·stale 은 build_report.py 의 facts() 가 계산한다 —
#      두 벌이 되면 주간보고와 세션 요약이 서로 다른 말을 한다.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# config.sh 는 Python 미발견 경고 등을 낼 수 있다. 훅은 조용해야 하므로 삼킨다.
# (set -e 누수도 되돌린다 — 훅은 중간에 죽으면 안 된다.)
. "$HERE/../scripts/lib/config.sh" 2>/dev/null || exit 0
set +e

[ -n "${PS_PY:-}" ] || exit 0

# .proj-sync/config.json 이 없는 곳(우산 저장소·임의 디렉토리)에서는 digest 가 빈 출력을 낸다.
DIGEST="$("$PS_PY" "$HERE/../scripts/build_report.py" --digest 2>/dev/null)"
[ -n "$DIGEST" ] || exit 0

# JSON 조립은 python 이 한다 — 본문에 따옴표·개행·백슬래시가 섞여 있어 셸 이스케이프로는 깨진다.
# (인코딩은 lib/config.sh 가 PYTHONUTF8·PYTHONIOENCODING 으로 고정한다.)
printf '%s' "$DIGEST" | "$PS_PY" -c '
import json, sys
ctx = sys.stdin.buffer.read().decode("utf-8", "replace")
if ctx.strip():
    out = {"hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext":
            "다음은 이 저장소의 **직전 작업 맥락**이다(git 으로 공유되는 revision 축에서 자동 추출). "
            "사용자가 이어서 작업할 가능성이 높으니 참고하되, 먼저 언급하지는 말 것.\n\n" + ctx,
    }}
    sys.stdout.buffer.write(json.dumps(out, ensure_ascii=True).encode("utf-8"))
' 2>/dev/null

exit 0
