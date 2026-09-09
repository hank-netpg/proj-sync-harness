#!/usr/bin/env bash
# proj-sync: Notion MCP 게시 **계획기** — 토큰 없음 · 네트워크 없음 · 판정만 한다.
#
#   기본 경로(claude_ai_mcp)에서는 로그인한 사용자의 claude.ai Notion 커넥터(MCP)가 게시한다.
#   그런데 이 저장소의 Notion 결함은 전부 **판정 로직**에서 났다 — NFD/NFC(#21·#22), 제목 충돌로
#   타 사업 페이지 덮어쓰기(2026-08-02), 스윕 과반(#31), 자기-상위(#53), 유형/상태 덮어쓰기(#52).
#   이 규칙을 스킬 산문으로 옮기면 에이전트가 매번 재구성하고 회귀 테스트가 불가능하다.
#   그래서 규칙은 여기(lib/notion_plan.py)에 두고, 에이전트는 계획 JSON 을 따라 MCP 호출만 한다.
#
# 사용:
#   notion_plan.sh plan                    # 대상·프로퍼티·본문 스테이징 → 계획 JSON(stdout)
#   notion_plan.sh plan --index <idx.json> # 문서함 인덱스(SQL 결과)를 대조해 action(create/update)·고아까지 채움
#   notion_plan.sh verify <key> <fetched.md> [plan.json]  # 게시 후 재조회한 본문이 구조를 잃지 않았는가
#
# 종료코드: 0 정상 · 1 verify 실패 · 2 config/입력 오류 · 3 publish.globs 미설정
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
set +e
ps_load_config || { echo "[notion-plan] config 로드 실패 (.proj-sync/config.json 필요)" >&2; exit 2; }

CMD="${1:-plan}"; shift 2>/dev/null || true
case "$CMD" in
  plan|verify)
    exec "$PS_PY" "$HERE/lib/notion_plan.py" "$CMD" --root "$PS_ROOT" --config "$PS_CONFIG" "$@"
    ;;
  *)
    echo "사용: notion_plan.sh plan [--index <idx.json>] | verify <key> <fetched.md> [plan.json]" >&2; exit 2 ;;
esac
