#!/usr/bin/env bash
# 회귀 테스트 — 팀 자격증명은 Slack 봇 토큰 하나 (v1.21.0 — 사용자 개인 계정 체제)
#
# 왜 있는가:
#   v1.8.1~v1.20.3 의 notion_publish.sh 는 팀 토큰이 캐시에 있으면 조용히 REST(integration 명의)로
#   승격했다. v1.21.0 은 팀 REST 경로 자체를 삭제했다 — 게시는 로그인한 사용자의 claude.ai Notion
#   커넥터(MCP, notion_plan.py 계획기)만 쓴다. 이 테스트는 그 삭제가 되돌아오지 않는지 지킨다:
#     · REST 스크립트(notion_publish.sh·notion_normalize.sh)·ps_notion_token 이 존재하지 않는다
#     · auth.sh 는 Slack 봇 토큰 하나만 판정하고, 구 opt-in 문구를 출력하지 않는다
#     · auth.sh set 이 캐시의 다른 키를 지우던 클로버가 재발하지 않는다
#
# 실행:  bash tests/test_notion_provider_gate.sh   (네트워크 불요)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTH="$ROOT/plugin/ax/scripts/auth.sh"
LIB="$ROOT/plugin/ax/scripts/lib/config.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1))
        else echo "  ✗ $1 — 기대=$2 실제=$3"; fail=$((fail+1)); fi; }

# ⚠ 토큰 모양의 리터럴을 파일에 두지 않는다(github_push.sh secret-scan 이 xoxb-/ntn_ 를 차단) — 런타임 조립.
FAKE_OTHER="ntn$(printf '_%s' 1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHI)"
FAKE_SLACK="xoxb$(printf -- '-%s' 1234567890 1234567890123 AbCdEfGhIjKlMnOpQrStUvWx)"
FAKE_SLACK2="xoxb$(printf -- '-%s' 9876543210 9876543210987 ZyXwVuTsRqPoNmLkJiHgFeDc)"

echo "── 팀 REST 경로가 존재하지 않는다 (v1.21.0 삭제 고정)"
chk "notion_publish.sh 부재"   "no" "$([ -f "$ROOT/plugin/ax/scripts/notion_publish.sh" ] && echo yes || echo no)"
chk "notion_normalize.sh 부재" "no" "$([ -f "$ROOT/plugin/ax/scripts/notion_normalize.sh" ] && echo yes || echo no)"
chk "team_digest.py 부재"      "no" "$([ -f "$ROOT/plugin/ax/scripts/team_digest.py" ] && echo yes || echo no)"
chk "lib/config.sh 에 ps_notion_token 없음" "0" "$(grep -c 'ps_notion_token()' "$LIB" || true)"
chk "MCP 계획기(notion_plan.py)는 존재"     "yes" "$([ -f "$ROOT/plugin/ax/scripts/lib/notion_plan.py" ] && echo yes || echo no)"

echo "── 스크립트 어디에도 구 opt-in 키를 읽는 코드가 없다"
RES="$(grep -rln 'PROJ_SYNC_NOTION_TOKEN\|PROJ_SYNC_GDRIVE_CLIENT_ID\|PROJ_SYNC_GDRIVE_SA_JSON_B64' "$ROOT/plugin/ax/scripts" 2>/dev/null || true)"
chk "plugin/ax/scripts 에 opt-in 키 참조 0건" "" "$RES"

CRED="$WORK/credentials"
export PS_GLOBAL_CRED="$CRED"
export PS_SECRETS_REPO="ax-harness/__no_such_repo_for_test__"   # 실 secrets repo 로 나가지 않게

echo "── auth.sh set 은 캐시의 다른 키를 보존한다 (종전 클로버 회귀)"
printf 'PROJ_SYNC_SLACK_BOT_TOKEN=%s\nPROJ_SYNC_OTHER_KEY=%s\n' "$FAKE_SLACK" "$FAKE_OTHER" > "$CRED"
bash "$AUTH" set "$FAKE_SLACK2" >/dev/null 2>&1; rc=$?
chk "auth.sh set → exit 0"           "0" "$rc"
chk "auth.sh set → Slack 값 교체"     "$FAKE_SLACK2" "$(grep '^PROJ_SYNC_SLACK_BOT_TOKEN=' "$CRED" | cut -d= -f2-)"
chk "auth.sh set → 다른 키 줄 보존"   "$FAKE_OTHER"  "$(grep '^PROJ_SYNC_OTHER_KEY=' "$CRED" | cut -d= -f2-)"
chk "auth.sh set → 줄 수 2"           "2" "$(grep -c . "$CRED")"
chk "auth.sh set → 임시파일 잔재 없음" "0" "$(ls -a "$WORK" | grep -c '^\.cred\.' || true)"

echo "── auth.sh show 는 Slack 만 판정하고, 구 opt-in 문구를 내지 않는다"
printf 'PROJ_SYNC_SLACK_BOT_TOKEN=%s\n' "$FAKE_SLACK" > "$CRED"
bash "$AUTH" show >"$WORK/out" 2>&1; rc=$?
chk "show(Slack 만) → exit 0"                 "0"  "$rc"
chk "show → Notion ✗ 를 띄우지 않음"           "no" "$(grep -q 'Notion API 토큰' "$WORK/out" && echo yes || echo no)"
chk "show → oauth_internal 문구 없음"          "no" "$(grep -q 'oauth_internal' "$WORK/out" && echo yes || echo no)"
chk "show → notion_api 문구 없음"              "no" "$(grep -q 'notion_api' "$WORK/out" && echo yes || echo no)"

echo "── auth.sh show 는 Slack 이 없으면 exit 1"
printf 'PROJ_SYNC_OTHER_KEY=%s\n' "$FAKE_OTHER" > "$CRED"
bash "$AUTH" show >"$WORK/out" 2>&1; rc=$?
chk "show(Slack 없음) → exit 1" "1" "$rc"

echo "── auth.sh fetch — 가짜 gh 로 Slack 한 줄만 내려와도 성공 (Notion 부재 ≠ 실패)"
FAKEBIN="$WORK/bin"; mkdir -p "$FAKEBIN"
B64="$(printf 'PROJ_SYNC_SLACK_BOT_TOKEN=%s\n' "$FAKE_SLACK" | base64 | tr -d '\n')"
printf '#!/bin/sh\necho "%s"\n' "$B64" > "$FAKEBIN/gh"; chmod +x "$FAKEBIN/gh"
export PATH="$FAKEBIN:$PATH"
SH_GH=no
[ "$(bash -c '. "'"$LIB"'"; command -v gh')" = "$FAKEBIN/gh" ] && SH_GH=yes
if [ "$SH_GH" = yes ]; then
  rm -f "$CRED"
  bash "$AUTH" fetch >"$WORK/out" 2>&1; rc=$?
  chk "fetch(Slack 만 내려옴) → exit 0" "0" "$rc"
  chk "fetch → 캐시에 Slack 기록"       "$FAKE_SLACK" "$(grep '^PROJ_SYNC_SLACK_BOT_TOKEN=' "$CRED" 2>/dev/null | cut -d= -f2-)"
  chk "fetch → 구 opt-in ℹ 문구 없음"    "no" "$(grep -q '캐시됨' "$WORK/out" && echo yes || echo no)"
else
  echo "  (gh 섀도잉 불가 — fetch 검사 건너뜀)"
fi

echo
echo "결과 — 통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
