#!/usr/bin/env bash
# 회귀 테스트 — 스캐폴드 예시값이 토큰 폴백을 막지 않는가 (issue #20)
#
# 왜 있는가:
#   실측(2026-08-09, 사업 17건) — .env 에 예시값이 남은 13건이 전부 doctor ✗ 였고,
#   /ax:sync 1단계가 doctor 라 그 사업의 동기화가 통째로 막혔다. 값을 채운 게 아니라
#   **지우기만 했더니** 17/17 이 ✓ 가 됐다. 「키가 없는 편이 정상 동작」하는 상태였다.
#   판정 지식이 doctor 한 곳에만 있었던 것이 원인이라, lib 로 옮긴 뒤에도 그대로인지 지킨다.
#
# 실행:  bash tests/test_token_placeholder.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/plugin/ax/scripts/lib/config.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

[ -f "$LIB" ] || { echo "✗ 대상 없음: $LIB" >&2; exit 1; }

# config.sh 는 set -euo pipefail 을 켠다 — 테스트는 끝까지 돌아야 하므로 되돌린다.
. "$LIB"
set +eu

pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1))
        else echo "  ✗ $1 — 기대=$2 실제=$3"; fail=$((fail+1)); fi; }
is_ph() { ps_is_placeholder "$1" && echo yes || echo no; }

echo "── 예시값으로 판정되어야 하는 것"
chk "빈 값"                    "yes" "$(is_ph '')"
chk "xoxb-여기에-봇토큰-입력"  "yes" "$(is_ph 'xoxb-여기에-봇토큰-입력')"
chk "ntn_여기에-토큰-입력"     "yes" "$(is_ph 'ntn_여기에-토큰-입력')"
chk "NAS비밀번호입력"          "yes" "$(is_ph 'NAS비밀번호입력')"
chk "<your-token>"             "yes" "$(is_ph '<your-token>')"
chk "YOUR_TOKEN_HERE"          "yes" "$(is_ph 'YOUR_TOKEN_HERE')"
# 스캐폴드가 실제로 배포하는 형태 — 이 둘이 잡히는 것이 판정의 존재 이유다.
chk "xoxb-... (env.template)"  "yes" "$(is_ph 'xoxb-...')"
chk "ntn_... (env.template)"   "yes" "$(is_ph 'ntn_...')"
chk "값 없는 접두 xoxb-"       "yes" "$(is_ph 'xoxb-')"
# ○ `xoxb-xxxx` 같은 임의의 더미는 **일부러 잡지 않는다.** 우리가 배포하는 값이 아니고,
#   그런 조각을 부분문자열로 잡으면 실토큰 오탐이 생긴다(아래 오탐 금지 절).
#   형식은 맞고 값이 가짜인 경우는 doctor 의 auth.test 가 invalid_auth 로 짚는다.

echo "── 실토큰으로 통과해야 하는 것 (오탐 금지)"
# ⚠ 토큰 **모양의 리터럴을 파일에 두지 않는다.** 이 레포·팀 사업 저장소의 secret-scan
#   (github_push.sh)이 xoxb-/ntn_/secret_ 패턴을 push 전에 차단하기 때문이다.
#   가짜라도 형태가 같으면 걸린다 — 스캐너는 진위를 모른다. 그래서 런타임에 조립한다.
DASH="-"
FAKE_SLACK="xoxb$(printf -- '-%s' 1234567890 1234567890123 AbCdEfGhIjKlMnOpQrStUvWx)"
FAKE_NOTION="ntn$(printf '_%s' 1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHI)"
FAKE_SECRET="secret$(printf '_%s' 1234567890abcdefghijklmnopqrstuvwxyzABCDEFG)"
chk "실 Slack 봇 토큰형"  "no" "$(is_ph "$FAKE_SLACK")"
chk "실 Notion 토큰형"    "no" "$(is_ph "$FAKE_NOTION")"
chk "실 secret_ 토큰형"   "no" "$(is_ph "$FAKE_SECRET")"
# ⚠ 오탐 회귀 — 종전 판정은 xxx/XXX 를 **부분문자열**로 잡아 실토큰을 예시값으로 버렸다.
#   버려진 토큰은 폴백으로 넘어가므로 「값이 있는데 안 쓰이는」 #20 의 반대 방향 실패가 된다.
#   랜덤 토큰에 xxx 가 끼는 일은 드물지만, 걸리면 원인을 찾기 매우 어렵다.
XXX_SLACK="xoxb$(printf -- '-%s' 2Fxxx9kQmZp 1234567890123 AbCdEfGhIjKlMnOpQrStUv)"
XXX_NOTION="ntn$(printf '_%s' 9aXXXbc1234567890abcdefghijklmnopqrstuvwxyzAB)"
chk "토큰 안의 xxx 는 예시값이 아님" "no" "$(is_ph "$XXX_SLACK")"
chk "토큰 안의 XXX 도 예시값이 아님" "no" "$(is_ph "$XXX_NOTION")"

echo "── 해석부가 예시값을 「없음」으로 다루는가 (핵심 회귀)"
# 예시값이 1순위로 채택되면 전역 캐시·팀 fetch 가 통째로 건너뛰어진다 — 그것이 #20 이었다.
FALLBACK_SLACK="$FAKE_SLACK"
export PROJ_SYNC_SLACK_BOT_TOKEN='xoxb-여기에-봇토큰-입력'
ps_cfg() { echo ""; }                                  # config 미로드 — 기본 token_ref 로 떨어진다
ps_global_token() { echo "$FALLBACK_SLACK"; }          # 전역 캐시에 실토큰이 있다고 가정
ps_fetch_team_token() { return 1; }
chk "예시값을 건너뛰고 전역 캐시를 채택" "$FALLBACK_SLACK" "$(ps_slack_token)"

echo "── 팀 토큰 확보 조건은 Slack 만 본다 (v1.21.0 — 유일한 팀 자격증명)"
# Notion 키가 캐시에 없어도 「팀 토큰 미확보」가 되면 setup/init/doctor 가 ✗ 를 띄우고 /ax:sync 가 막힌다.
CRED_FILE="$WORK/credentials"; printf 'PROJ_SYNC_SLACK_BOT_TOKEN=%s\n' "$FAKE_SLACK" > "$CRED_FILE"
PS_GLOBAL_CRED="$CRED_FILE"
ps_global_token() { grep -E "^${1:-PROJ_SYNC_SLACK_BOT_TOKEN}=" "$PS_GLOBAL_CRED" 2>/dev/null | cut -d= -f2-; }
chk "Slack 만 있어도 확보(0)"             "0" "$(ps_have_team_tokens; echo $?)"
chk "명시 키(임의) 요구 시에는 미확보(1)"   "1" "$(ps_have_team_tokens PROJ_SYNC_OTHER_KEY; echo $?)"
# ps_cred_set 은 같은 KEY 만 바꾸고 다른 줄을 보존한다 (종전 auth.sh set 은 파일을 통째로 덮었다).
printf 'PROJ_SYNC_OTHER_KEY=%s\n' "$FAKE_NOTION" >> "$CRED_FILE"
ps_cred_set PROJ_SYNC_SLACK_BOT_TOKEN "$XXX_SLACK"
chk "ps_cred_set — Slack 값 교체"          "$XXX_SLACK"   "$(ps_global_token PROJ_SYNC_SLACK_BOT_TOKEN)"
chk "ps_cred_set — 다른 키 줄 보존"        "$FAKE_NOTION" "$(ps_global_token PROJ_SYNC_OTHER_KEY)"
chk "ps_cred_set — 줄 수 2 (중복 없음)"     "2" "$(grep -c . "$CRED_FILE")"

echo "── 실토큰이 .env 에 있으면 그대로 1순위 (폴백보다 우선)"
export PROJ_SYNC_SLACK_BOT_TOKEN="$FAKE_SLACK"
ps_global_token() { echo "xoxb${DASH}SHOULD${DASH}NOT${DASH}BE${DASH}USED"; }
chk "env 실토큰 우선" "$FAKE_SLACK" "$(ps_slack_token)"

echo "── 스캐폴드 템플릿이 예시값을 활성 상태로 두지 않는가"
TPL="$ROOT/plugin/ax/templates/env.template"
chk "활성(비주석) 토큰 대입 줄 0개" "0" \
  "$(grep -cE '^[[:space:]]*PROJ_SYNC_[A-Z_]*TOKEN[A-Z_]*=' "$TPL" 2>/dev/null || true)"

echo
echo "결과 — 통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
