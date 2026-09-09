#!/usr/bin/env bash
# 커밋 메시지 규약 검사 — Conventional Commits v1.0.0 + git 72칸 규칙
#
# 원칙: **코드가 「무엇」을 말하니 커밋은 「왜」를 말한다.**
#   diff 를 보면 무엇이 바뀌었는지는 안다. 커밋이 그것을 다시 적으면 두 벌이 된다.
#   6개월 뒤 이 줄을 blame 하는 사람에게 필요한 것은 **그때 무엇이 문제였는가** 다.
#
# 한글 기준이 다르다:
#   72 는 **문자 수가 아니라 표시 폭**이다. `git log` 는 본문을 4칸 들여쓰므로 80칸
#   터미널에 맞추려면 76칸이 상한이고, 관례상 72 를 쓴다. 한글은 한 자가 2칸이라
#   72칸 ≈ 한글 36자다. 문자 수로만 재면 한글 커밋은 전부 통과하면서 실제로는 접힌다.
#     실측(2026-08-30, 최근 60커밋): 문자 수 기준 제목 위반 0건 → 표시 폭 기준 17건.
#     본문은 54/60 커밋·342줄이 72칸을 넘었고 269줄이 80칸에서 접혔다.
#
# 사용:
#   lint_commit_msg.sh <파일>      # commit-msg 훅 (메시지 파일)
#   lint_commit_msg.sh --title "제목"   # PR 제목만 (스쿼시 머지 = PR 제목이 커밋 제목)
#   echo "msg" | lint_commit_msg.sh -   # stdin
#
# 종료코드: 0 통과 · 1 위반
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# config.sh 는 PS_PY(파이썬 실행기)와 UTF-8 인코딩 고정만 쓴다. 없으면 python3 로 폴백.
. "$HERE/lib/config.sh" 2>/dev/null || true
PY="${PS_PY:-$(command -v python3 || command -v python)}"
[ -n "$PY" ] || { echo "[commit-lint] python 없음 — 검사를 건너뜁니다" >&2; exit 0; }

MODE=msg; ARG=""
case "${1:-}" in
  --title) MODE=title; ARG="${2:-}" ;;
  -)       MODE=msg;   ARG="-" ;;
  "")      echo "사용: $0 <파일> | --title \"제목\" | -" >&2; exit 2 ;;
  *)       MODE=msg;   ARG="$1" ;;
esac

if [ "$MODE" = title ]; then
  printf '%s\n' "$ARG" | "$PY" "$HERE/lib/commit_lint.py" --title
elif [ "$ARG" = "-" ]; then
  "$PY" "$HERE/lib/commit_lint.py"
else
  [ -f "$ARG" ] || { echo "[commit-lint] 메시지 파일 없음: $ARG" >&2; exit 2; }
  "$PY" "$HERE/lib/commit_lint.py" < "$ARG"
fi
