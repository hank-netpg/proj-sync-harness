#!/usr/bin/env bash
# 회귀 테스트 — Notion MCP 게시 계획기(notion_plan.sh)가 REST 와 같은 판정을 내는가 (v1.21.0)
#
# 왜 있는가:
#   MCP 경로는 에이전트가 게시하므로, 판정 규칙이 스크립트에 없으면 매번 재구성된다. 이 테스트는
#   REST 경로가 사고로 배운 규칙을 계획기가 그대로 내는지 지킨다 —
#     · 출처경로는 NFC (#21·#22)            · 경로별 유형/상태(99_아카이브·management)
#     · 루트 문서는 상위 항목 없음(#53)     · 갱신 시 유형/상태 미포함(#52)
#     · 동명이나 출처경로 다른 페이지는 남의 것(2026-08-02)   · keep 비면·과반이면 스윕 중단(#31)
#     · verify 가 헤딩 소실을 잡음
#
# 실행:  bash tests/test_notion_plan.sh   (네트워크·토큰 불요)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN="$ROOT/plugin/ax/scripts/notion_plan.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
PY="$(command -v python3 || command -v python)"

pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1))
        else echo "  ✗ $1 — 기대=$2 실제=$3"; fail=$((fail+1)); fi; }
jq_() { "$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2" 2>&1; }

# ── 픽스처 사업 ──────────────────────────────────────────────
PROJ="$WORK/proj"; mkdir -p "$PROJ/.proj-sync" "$PROJ/reference/drafts/10_착수" "$PROJ/reference/drafts/99_아카이브" \
  "$PROJ/reference/management/risk" "$PROJ/reference/management/reports"
cat > "$PROJ/.proj-sync/config.json" <<'JSON'
{"version":1,"project":{"id":"plantest","name":"t","root_page_title":"[Proj]플랜테스트"},
 "notion":{"enabled":true,"data_source_id":"bf6c317e-8b47-4e32-94b6-b72cf9b1e6df","project_tag":"플랜태그",
  "properties":{"title":"문서명","type":"유형","status":"상태","project":"프로젝트","applies_to":"적용대상","parent":"상위 항목"},
  "publish":{"globs":["reference/drafts/**/*.md","reference/management/**/*.md"],
             "exclude_globs":["reference/management/reports/**/*.md"],"type":"기술문서","status":"작성중"}}}
JSON
# NFD 파일명(macOS 가 저장하는 형태) — 계획의 src 는 NFC 여야 한다.
NFD_NAME="$("$PY" -c 'import unicodedata;print(unicodedata.normalize("NFD","착수신고서"))')"
printf '# 착수신고서\n\n본문\n\n#### 깊은 제목\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```mermaid\ngraph TD; A-->B\n```\n' > "$PROJ/reference/drafts/10_착수/$NFD_NAME.md"
printf '# \xe2\x80\x8b제로폭 문서\n\n내용\xe2\x80\x8b\n' > "$PROJ/reference/drafts/10_착수/zw.md"          # U+200B 제거 대상
printf '# 옛 문서\n\n지난 것\n' > "$PROJ/reference/drafts/99_아카이브/old.md"
printf '# 위험관리대장\n\n| 위험 |\n|---|\n| x |\n' > "$PROJ/reference/management/risk/risk.md"
printf '# 주간보고\n' > "$PROJ/reference/management/reports/w1.md"                                   # exclude 대상
printf '# [Proj]플랜테스트\n\n루트\n' > "$PROJ/reference/drafts/overview.md"                            # 루트 문서

run_plan() { ( cd "$PROJ" && bash "$PLAN" plan --stage-dir "$WORK/stage" "$@" >"$WORK/out" 2>"$WORK/err" ); echo $?; }
P="$WORK/stage/plan.json"

echo "── plan (인덱스 없음): 대상·경로 규칙·NFC·스테이징"
rc="$(run_plan)"
chk "exit 0"                                   "0" "$rc"
chk "대상 5건(reports 제외)"                    "5" "$(jq_ "$P" 'len(d["docs"])')"
chk "src 가 NFC (NFD 파일명 → 완성형)"            "plantest/reference/drafts/10_착수/착수신고서.md" \
  "$(jq_ "$P" '[x["src"] for x in d["docs"] if x["src"].endswith("착수신고서.md")][0]')"
chk "99_아카이브 → 상태=아카이브·유형 기본"        "기술문서/아카이브" \
  "$(jq_ "$P" '(lambda x: x["type"]+"/"+x["status"])([x for x in d["docs"] if x["key"].endswith("old.md")][0])')"
chk "management → 현황/현행화문서"                "현황/현행화문서" \
  "$(jq_ "$P" '(lambda x: x["type"]+"/"+x["status"])([x for x in d["docs"] if x["key"].endswith("risk.md")][0])')"
chk "그 외 → config 기본값"                       "기술문서/작성중" \
  "$(jq_ "$P" '(lambda x: x["type"]+"/"+x["status"])([x for x in d["docs"] if x["key"].endswith("zw.md")][0])')"
chk "루트 문서 표시(is_root_doc)"                  "True" "$(jq_ "$P" '[x["is_root_doc"] for x in d["docs"] if x["key"].endswith("overview.md")][0]')"
chk "expect 집계(H2 → h4 접힘 포함 · T1 · C1)"     "{'heading': 2, 'table': 1, 'code': 1}" \
  "$(jq_ "$P" '[x["expect"] for x in d["docs"] if x["src"].endswith("착수신고서.md")][0]')"
BP="$(jq_ "$P" '[x["body_path"] for x in d["docs"] if x["src"].endswith("착수신고서.md")][0]')"
chk "본문 스테이징: h4 → ###"                     "1" "$(grep -c '^### 깊은 제목' "$BP")"
ZP="$(jq_ "$P" '[x["body_path"] for x in d["docs"] if x["key"].endswith("zw.md")][0]')"
chk "본문 스테이징: 제로폭 제거"                    "0" "$(grep -c $'\xe2\x80\x8b' "$ZP" || true)"
chk "action 은 인덱스 전엔 null"                   "None" "$(jq_ "$P" 'd["docs"][0]["action"]')"
chk "lookup_sql 이 프로젝트 태그로 거른다"          "True" "$(jq_ "$P" '"\"프로젝트\" LIKE" in d["lookup_sql"] and "플랜태그" in d["lookup_sql"]')"
chk "출처경로 없는 페이지도 조회한다(제목 폴백용)"     "False" "$(jq_ "$P" '"출처경로\" IS NOT NULL" in d["lookup_sql"]')"

echo "── plan --index: 매칭·프로퍼티·루트·고아"
ROOT_ID="0123456789abcdef0123456789abcdef"; OLD_ID="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1"; OTHER_ID="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb2"
LEGACY_ID="ccccccccccccccccccccccccccccccc3"; ORPH_ID="ddddddddddddddddddddddddddddddd4"; ARCH_ID="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeee5"
cat > "$WORK/idx.json" <<JSON
{"results":[
 {"url":"https://app.notion.com/p/$ROOT_ID","문서명":"[Proj]플랜테스트","상태":"완료","유형":"제안서/백서","출처경로":"plantest/reference/drafts/overview.md","상위 항목":""},
 {"url":"https://app.notion.com/p/$OLD_ID","문서명":"옛 문서","상태":"현행화문서","유형":"현황","출처경로":"plantest/reference/drafts/99_아카이브/old.md","상위 항목":"[\"https://app.notion.com/p/$ROOT_ID\"]"},
 {"url":"https://app.notion.com/p/$OTHER_ID","문서명":"착수신고서","상태":"완료","유형":"기술문서","출처경로":"otherproj/reference/drafts/10_착수/착수신고서.md","상위 항목":""},
 {"url":"https://app.notion.com/p/$LEGACY_ID","문서명":"위험관리대장","상태":"","유형":"","출처경로":"","상위 항목":""},
 {"url":"https://app.notion.com/p/$ORPH_ID","문서명":"사라진 문서","상태":"완료","유형":"기술문서","출처경로":"plantest/reference/drafts/gone.md","상위 항목":""},
 {"url":"https://app.notion.com/p/$ARCH_ID","문서명":"이미 아카이브","상태":"아카이브","유형":"기술문서","출처경로":"plantest/reference/drafts/archived.md","상위 항목":""},
 {"url":"https://app.notion.com/p/$ORPH_ID","문서명":"사라진 문서(커서 중복)","상태":"완료","유형":"기술문서","출처경로":"plantest/reference/drafts/gone.md","상위 항목":""}
]}
JSON
rc="$(run_plan --index "$WORK/idx.json")"
chk "exit 0"                                     "0" "$rc"
chk "인덱스 행 distinct(7→6)"                      "6" "$(jq_ "$P" 'd["index_rows"]')"
chk "루트 id 를 인덱스에서 해석"                   "$ROOT_ID" "$(jq_ "$P" 'd["root"]["id"]')"
D_OLD='[x for x in d["docs"] if x["key"].endswith("old.md")][0]'
chk "출처경로 일치 → update"                       "update/$OLD_ID/source" "$(jq_ "$P" "(lambda x: x['action']+'/'+x['page_id']+'/'+x['matched_by'])($D_OLD)")"
chk "update 프로퍼티에 유형·상태 없음(기존 값 보존 #52)" "False" "$(jq_ "$P" "any(k in ${D_OLD}['properties'] for k in ('유형','상태'))")"
chk "update 프로퍼티에 상위 항목 없음(이미 있음)"        "False" "$(jq_ "$P" "'상위 항목' in ${D_OLD}['properties']")"
chk "update 프로퍼티 = 문서명·출처경로·프로젝트"        "['문서명', '출처경로', '프로젝트']" "$(jq_ "$P" "sorted(${D_OLD}['properties'].keys(), key=lambda k: ['문서명','출처경로','프로젝트'].index(k))")"
D_CH='[x for x in d["docs"] if x["src"].endswith("착수신고서.md")][0]'
chk "동명이지만 출처경로가 타 사업 → create(남의 페이지 안 씀)" "create" "$(jq_ "$P" "${D_CH}['action']")"
chk "create 프로퍼티에 유형·상태·상위 항목 있음"          "True" "$(jq_ "$P" "all(k in ${D_CH}['properties'] for k in ('유형','상태','상위 항목','프로젝트','출처경로','문서명'))")"
chk "create 상위 항목 = 루트"                          "['$ROOT_ID']" "$(jq_ "$P" "${D_CH}['properties']['상위 항목']")"
D_RISK='[x for x in d["docs"] if x["key"].endswith("risk.md")][0]'
chk "출처경로 빈 동명 페이지 → 제목 폴백 update"          "update/$LEGACY_ID/title" "$(jq_ "$P" "(lambda x: x['action']+'/'+x['page_id']+'/'+x['matched_by'])($D_RISK)")"
chk "폴백 update: 기존 유형/상태가 비어 있으면 채운다"      "현황/현행화문서" "$(jq_ "$P" "${D_RISK}['properties']['유형']+'/'+${D_RISK}['properties']['상태']")"
chk "폴백 update: 상위가 비어 있으면 루트로"              "['$ROOT_ID']" "$(jq_ "$P" "${D_RISK}['properties']['상위 항목']")"
D_ROOT='[x for x in d["docs"] if x["key"].endswith("overview.md")][0]'
chk "루트 문서 → update(자기 자신)"                     "update/$ROOT_ID" "$(jq_ "$P" "${D_ROOT}['action']+'/'+${D_ROOT}['page_id']")"
chk "루트 문서 프로퍼티에 상위 항목 없음(#53)"            "False" "$(jq_ "$P" "'상위 항목' in ${D_ROOT}['properties']")"
chk "고아 = 사라진 문서 1건(아카이브·현행 제외)"          "['$ORPH_ID']" "$(jq_ "$P" '[o["page_id"] for o in d["orphans"]]')"
chk "스윕 분모 = 출처경로 있는 페이지 5건"               "5" "$(jq_ "$P" 'd["sweep_seen"]')"
chk "과반 아님 → abort 없음"                          "None" "$(jq_ "$P" 'd["abort"]')"

echo "── 스윕 가드"
# 과반: 인덱스에 고아를 4건 더 넣으면 5/9 → 과반
"$PY" - "$WORK/idx.json" "$WORK/idx_major.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
for i in range(4):
    d["results"].append({"url":"https://app.notion.com/p/%s" % (("%d"%i)*32),"문서명":"고아%d"%i,"상태":"완료","유형":"기술문서","출처경로":"plantest/gone%d.md"%i,"상위 항목":""})
json.dump(d,open(sys.argv[2],"w"),ensure_ascii=False)
PY
rc="$(run_plan --index "$WORK/idx_major.json")"
chk "과반 → abort=majority"                       "majority" "$(jq_ "$P" 'd["abort"]["code"]')"
rc="$(run_plan --index "$WORK/idx_major.json" --force-sweep)"
chk "--force-sweep → abort 해제"                   "None" "$(jq_ "$P" 'd["abort"]')"
rc="$(NP_SWEEP_FORCE=1 run_plan --index "$WORK/idx_major.json")"
chk "NP_SWEEP_FORCE=1 도 동일"                     "None" "$(jq_ "$P" 'd["abort"]')"
# keep 비면: globs 가 아무것도 못 잡게
"$PY" - "$PROJ/.proj-sync/config.json" <<'PY'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); c["notion"]["publish"]["globs"]=["nothing/**/*.md"]; json.dump(c,open(p,"w"),ensure_ascii=False)
PY
rc="$(run_plan --index "$WORK/idx.json")"
chk "대상 0건 → abort=keep_empty"                 "keep_empty" "$(jq_ "$P" 'd["abort"]["code"]')"
chk "대상 0건이어도 exit 0"                        "0" "$rc"
# globs 미설정 → 3
"$PY" - "$PROJ/.proj-sync/config.json" <<'PY'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); del c["notion"]["publish"]["globs"]; json.dump(c,open(p,"w"),ensure_ascii=False)
PY
rc="$(run_plan)"
chk "globs 미설정 → exit 3"                        "3" "$rc"

echo "── 문서명 고정(notion.publish.titles): 큐레이션된 제목을 H1 로 덮지 않는다"
"$PY" - "$PROJ/.proj-sync/config.json" <<'PY'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); c["notion"]["publish"]["globs"]=["reference/drafts/**/*.md"]
c["notion"]["publish"]["titles"]={"reference/drafts/10_착수/zw.md":"[도구]고정 제목"}; json.dump(c,open(p,"w"),ensure_ascii=False)
PY
run_plan >/dev/null
chk "titles 에 있는 문서 → 고정 제목"              "[도구]고정 제목" "$(jq_ "$P" '[x["title"] for x in d["docs"] if x["key"].endswith("zw.md")][0]')"
chk "titles 에 없는 문서 → H1"                     "옛 문서" "$(jq_ "$P" '[x["title"] for x in d["docs"] if x["key"].endswith("old.md")][0]')"
"$PY" - "$PROJ/.proj-sync/config.json" <<'PY'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); del c["notion"]["publish"]["titles"]; json.dump(c,open(p,"w"),ensure_ascii=False)
PY

echo "── verify"
"$PY" - "$PROJ/.proj-sync/config.json" <<'PY'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); c["notion"]["publish"]["globs"]=["reference/drafts/**/*.md"]; json.dump(c,open(p,"w"),ensure_ascii=False)
PY
run_plan >/dev/null
KEY="reference/drafts/10_착수/$NFD_NAME.md"
printf '# 착수신고서\n\n본문\n\n### 깊은 제목\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```mermaid\ngraph TD; A-->B\n```\n' > "$WORK/fetched_ok.md"
printf '# 착수신고서\n\n본문 깊은 제목\n\n| a | b |\n|---|---|\n| 1 | 2 |\n' > "$WORK/fetched_lost.md"
( cd "$PROJ" && bash "$PLAN" verify "$KEY" "$WORK/fetched_ok.md" --plan "$P" >"$WORK/out" 2>&1 ); rc=$?
chk "구조 보존 → exit 0"                          "0" "$rc"
( cd "$PROJ" && bash "$PLAN" verify "$KEY" "$WORK/fetched_lost.md" --plan "$P" >"$WORK/out" 2>&1 ); rc=$?
chk "헤딩·코드 소실 → exit 1"                       "1" "$rc"
chk "소실 코드가 보고됨"                            "yes" "$(grep -q 'heading_lost' "$WORK/out" && grep -q 'code_lost' "$WORK/out" && echo yes || echo no)"
( cd "$PROJ" && bash "$PLAN" verify "없는/키.md" "$WORK/fetched_ok.md" --plan "$P" >"$WORK/out" 2>&1 ); rc=$?
chk "계획에 없는 key → exit 2"                     "2" "$rc"

echo "── 안전: 계획기는 네트워크·토큰을 만지지 않는다"
chk "curl/urllib/requests/토큰 참조 0"            "0" "$(grep -cE 'curl|urllib|requests|NOTION_TOKEN|api\.notion\.com' "$ROOT/plugin/ax/scripts/lib/notion_plan.py" || true)"

echo
echo "결과 — 통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
