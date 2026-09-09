#!/usr/bin/env bash
# 회귀 테스트 — 커밋 메시지 규약 검사기가 실제로 잡는가
#
# 근거: Conventional Commits v1.0.0 · git 72칸 규칙
# 원칙: 코드가 「무엇」을 말하니 커밋은 「왜」를 말한다.
#
# 왜 있는가:
#   72 는 문자 수가 아니라 **표시 폭**이다. 한글은 한 자가 2칸이라, 문자 수로 재는
#   검사기는 한글 커밋을 전부 통과시키면서 터미널에서는 접히게 둔다.
#     실측(2026-08-30, 최근 60커밋): 문자 수 기준 제목 위반 0건 → 표시 폭 기준 17건.
#   대조군으로 「잡아야 하는 것」을 매번 증명한다 — 검사기가 죽으면 전건 통과가 되기 때문이다.
#
# 실행:  bash tests/test_commit_lint.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="$ROOT/plugin/ax/scripts/lint_commit_msg.sh"

pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1))
        else echo "  ✗ $1 — 기대=$2 실제=$3"; fail=$((fail+1)); fi; }
# rc <메시지> → 종료코드 (0 통과 · 1 위반)
rc() { printf '%s' "$1" | bash "$LINT" - >/dev/null 2>&1; echo $?; }
rct() { bash "$LINT" --title "$1" >/dev/null 2>&1; echo $?; }

[ -x "$LINT" ] || { echo "✗ lint_commit_msg.sh 없음" >&2; exit 1; }

echo "[1] 규약을 지킨 메시지는 통과한다"
chk "type(scope) + 본문 + 꼬리말" "0" \
  "$(rc 'fix(notion): 재게시가 게시본을 불리던 문제

삭제가 한 페이지만 돌아 100블록 초과 문서가 매번 불어났다.

Closes #46')"
chk "scope 없는 형태"        "0" "$(rc 'docs: 커밋 규약 문서 추가')"
chk "破壞적 변경 표기(!)"     "0" "$(rc 'feat(api)!: 토큰 해석 순서를 바꾼다

기존 .env 우선을 캐시 우선으로 뒤집는다.

BREAKING CHANGE: .env 토큰이 더 이상 최우선이 아니다')"

echo "[2] 대조군 — 잡아야 하는 것"
chk "형식 아님(type 없음)"    "1" "$(rc '재게시가 게시본을 불리던 문제

본문.')"
chk "허용되지 않는 type(release)" "1" \
  "$(rc 'release: v1.20.0 — 두 갈래 통합

본문.')"
chk "제목 마침표"             "1" "$(rc 'docs: 규약 문서를 추가한다.')"
chk "feat 인데 본문 없음"      "1" "$(rc 'feat(hook): 세션 시작 훅 추가')"
chk "fix 인데 본문 없음"       "1" "$(rc 'fix(x): 오타 수정')"
chk "제목·본문 사이 빈 줄 없음" "1" \
  "$(rc 'fix(x): 짧은 제목
바로 본문이 붙었다.')"

echo "[3] 표시 폭 — 한글은 한 자가 2칸"
# 한글 40자 = 80칸 > 72칸. 문자 수로 재는 검사기는 이걸 통과시킨다.
LONG_KO='가나다라마바사아자차카타파하가나다라마바사아자차카타파하가나다라마바사아자차카타파하'
chk "제목 표시 폭 초과를 잡는다" "1" "$(rc "fix(x): $LONG_KO")"
chk "본문 표시 폭 초과를 잡는다" "1" \
  "$(rc "fix(x): 짧은 제목

$LONG_KO")"
# 영문 71칸은 통과해야 한다 — 폭 계산이 CJK 에만 걸리는지 확인
ASCII69="$(python3 -c 'print("a"*57)')"
chk "영문 짧은 제목은 통과"    "0" "$(rc "fix(x): $ASCII69

본문.")"

echo "[4] PR 제목 — 스쿼시 머지라 곧 커밋 제목이 된다"
# GitHub 이 ` (#123)` 을 붙이므로 상한이 64칸이다.
chk "64칸 이하 PR 제목 통과"   "0" "$(rct 'fix(notion): 재게시가 게시본을 불리던 문제')"
chk "64칸 초과 PR 제목 차단"   "1" \
  "$(rct 'fix(notion): 재게시가 게시본을 불리던 문제와 엣지 차단 오인을 함께 고친다')"
# 이미 (#NN) 이 붙은 제목도 형식 판정은 되어야 한다
chk "(#NN) 붙은 제목도 파싱된다" "0" "$(rct 'fix(notion): 게시본이 불어나던 문제 (#46)')"

echo "[5] 소스 불변식"
chk "표시 폭 계산에 east_asian_width 를 쓴다" "1" \
  "$(grep -c 'east_asian_width' "$ROOT/plugin/ax/scripts/lib/commit_lint.py" || true)"
chk "commit-msg 훅이 있다" "1" "$([ -x "$ROOT/.githooks/commit-msg" ] && echo 1 || echo 0)"
chk "CI 가 PR 제목을 검사한다" "1" \
  "$(grep -c 'lint_commit_msg.sh --title' "$ROOT/.github/workflows/lint.yml" || true)"
chk "규약 문서가 있다" "1" "$([ -f "$ROOT/plugin/ax/COMMIT_CONVENTION.md" ] && echo 1 || echo 0)"

echo "------------------------------------"
echo "결과: ✓ $pass / ✗ $fail"
[ "$fail" -eq 0 ]
