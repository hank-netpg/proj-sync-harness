#!/usr/bin/env bash
# 회귀 테스트 — 지식맵(docquark)이 그래프로서 성립하는가
#
# 왜 있는가:
#   SPEC §지식맵은 간선을 **양방향**(page→req, req→page)으로 적어 두었는데, 구현은 오랫동안
#   page→req 만 만들었다. 그래서 "요구사항 X 를 덮는 페이지가 어디인가" 는 `ls` 한 번으로
#   답이 나오지 않고 전체 페이지를 훑어야 했다 — 인덱스가 있는데 한쪽만 있는 상태였다.
#   문서가 참이라고 말하는 것을 검사가 지키게 한다.
#
#   두 번째로 지키는 것은 **링크 모드**다. 간선은 심볼릭 링크인데 심링크는 POSIX 전용이고,
#   이 저장소는 윈도우 설치본을 함께 배포한다(A6 환경 동질성). 심링크를 못 만드는 환경에서
#   조용히 반쪽 그래프가 되면 에이전트는 "간선이 없다" 를 "관계가 없다" 로 읽는다.
#   그래서 모드를 프로브해 `_LINKMODE` 에 남기고, 안내문(ai_context_guide.txt)이 그 모드를
#   설명하는지까지 본다.
#
# 실행:  bash tests/test_docquark_graph.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DQ="$ROOT/plugin/ax/scripts/docquark.mjs"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

command -v node >/dev/null || { echo "  ℹ node 없음 — 건너뜀"; exit 0; }

pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1))
        else echo "  ✗ $1 — 기대=$2 실제=$3"; fail=$((fail+1)); fi; }

mkdir -p "$WORK/proposal"
cat > "$WORK/proposal/requirements.json" <<'J'
{"items":[
 {"id":"SFR-001","summary":"문헌 분석","category":"기능","담당":"주관사","배점":"기능15","toc_paths":["III-1-1"]},
 {"id":"DAR-002","summary":"지식그래프","category":"데이터","담당":"주관사","배점":"데이터10","toc_paths":["III-2-1"]},
 {"id":"ORP-009","summary":"고아 요구사항","category":"기능","담당":"주관사"}
]}
J
cat > "$WORK/proposal/toc.json" <<'J'
{"chapters":[{"id":"III","title":"기술및기능","sections":[
 {"id":"1","title":"기능요구사항","배점":15,"pages":[{"page_id":"III-1-1","title":"분석","req_ids":["SFR-001","NOPE-999"]}]},
 {"id":"2","title":"데이터","배점":10,"pages":[{"page_id":"III-2-1","title":"KG","req_ids":["DAR-002"]}]}]}]}
J

( cd "$WORK" && node "$DQ" proposal knowledge >/dev/null 2>&1 )
K="$WORK/knowledge"

echo "[1] 간선 — 양방향인가"
chk "page→req (III-1-1 → SFR-001)" 1 \
  "$(ls "$K"/quark/toc/III__*/1__*/III-1-1__*/_axon/ 2>/dev/null | grep -c '^req__SFR-001')"
chk "req→page (SFR-001 → III-1-1)" 1 \
  "$(ls "$K"/quark/req/SFR-001__*/_axon/ 2>/dev/null | grep -c '^toc__III-1-1')"
chk "req→page (DAR-002 → III-2-1)" 1 \
  "$(ls "$K"/quark/req/DAR-002__*/_axon/ 2>/dev/null | grep -c '^toc__III-2-1')"
# 간선을 따라가면 실제 노드에 닿아야 한다 — 링크가 걸려만 있고 끊겨 있으면 그래프가 아니다.
chk "간선 추적 가능(meta.md 도달)" 0 \
  "$( [ -r "$(echo "$K"/quark/req/SFR-001__*/_axon/toc__III-1-1)/meta.md" ] && echo 0 || echo 1 )"

echo "[2] 역인덱스 — _mirror"
chk "by_담당/주관사 3건" 3 "$(ls "$K"/_mirror/by_담당/주관사/ 2>/dev/null | wc -l | tr -d ' ')"
chk "by_kind/기능 2건"   2 "$(ls "$K"/_mirror/by_kind/기능/ 2>/dev/null | wc -l | tr -d ' ')"

echo "[3] 참조 무결성 — 끊긴 간선·고아를 잡는가"
chk "dangling(NOPE-999) 경고" 1 "$(grep -c 'NOPE-999' "$K/_UNMAPPED.md" 2>/dev/null)"
chk "고아(ORP-009) 경고"      1 "$(grep -c 'ORP-009'  "$K/_UNMAPPED.md" 2>/dev/null)"
# 정상 요구사항이 경고에 섞이면 경고가 신호를 잃는다.
chk "정상 req 는 경고 없음"    0 "$(grep -c 'SFR-001' "$K/_UNMAPPED.md" 2>/dev/null)"

echo "[4] 링크 모드 — 프로브 결과가 기록·안내되는가"
MODE="$(cat "$K/_LINKMODE" 2>/dev/null | tr -d '\n')"
chk "_LINKMODE 값이 symlink|file" 0 \
  "$( case "$MODE" in symlink|file) echo 0;; *) echo 1;; esac )"
if [ "$MODE" = "symlink" ]; then
  chk "안내문이 심링크 모드를 설명" 1 "$(grep -c '심볼릭 링크' "$K/ai_context_guide.txt")"
else
  chk "안내문이 .link 파일 모드를 설명" 1 "$(grep -c '\.link' "$K/ai_context_guide.txt")"
fi
chk "안내문에 req→page 순회법 존재" 1 \
  "$(grep -c 'quark/req/{ID}__\*/_axon/' "$K/ai_context_guide.txt")"

echo
echo "통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
