#!/usr/bin/env bash
# proj-sync Slack API 헬퍼 — auth.test / scope 점검 / files.list(pagination)
# 선행: source config.sh && ps_load_config (PS_SLACK_TOKEN 사용)
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# 봇 토큰 확보 (호출 전 ps_slack_token 결과를 PS_SLACK_TOKEN에 넣어두거나 여기서 해석)
ps_slack_init_token() {
  PS_SLACK_TOKEN="${PS_SLACK_TOKEN:-$(ps_slack_token)}"
  if [ -z "$PS_SLACK_TOKEN" ] || [ "$PS_SLACK_TOKEN" = "__GH_AUTH__" ]; then
    echo "[proj-sync] Slack 봇 토큰 없음. .env의 PROJ_SYNC_SLACK_BOT_TOKEN 확인." >&2
    return 1
  fi
}

# 토큰을 argv(ps 노출) 대신 stdin config(-K)로 전달하는 curl 래퍼
ps_curl() {
  curl --config <(printf 'header = "Authorization: Bearer %s"\n' "$PS_SLACK_TOKEN") "$@"
}

# ── 레이트리밋 대응 ────────────────────────────────────────────
# Slack Tier 3(≈50 req/min)에서 채널 전수 스윕은 수백 호출이 된다. 종전에는
# 백오프가 전혀 없어 429 가 나면 history 는 조용히 루프를 끝내고 replies 는
# 「답글 없음」을 반환했다 — 즉 **데이터가 빈 것을 알 수 없었다**.
# 여기서 429/5xx 를 재시도하고, 그래도 실패하면 명시적으로 실패시킨다.
PS_SLACK_MAX_RETRY="${PS_SLACK_MAX_RETRY:-5}"
PS_SLACK_MIN_INTERVAL="${PS_SLACK_MIN_INTERVAL:-1.2}"   # 호출 간 최소 간격(초)
PS_SLACK_RL_HITS=0                                       # 429 발생 횟수(누적)

# GET 호출 1건. 인자: url 출력파일. 성공 시 0, 재시도 소진 시 1.
# 응답 바디의 ok:false 는 여기서 판정하지 않는다(호출부가 error 코드를 봐야 하므로).
ps_slack_get() {
  local url="$1" out="$2" try=0 code wait hdr
  hdr="$(mktemp)"
  while :; do
    code="$(ps_curl -s -D "$hdr" -o "$out" -w '%{http_code}' "$url" || echo 000)"
    if [ "$code" = "429" ]; then
      PS_SLACK_RL_HITS=$((PS_SLACK_RL_HITS+1))
      wait="$(grep -i '^retry-after:' "$hdr" | sed 's/^[^:]*: *//' | tr -d '\r' | head -1)"
      [ -n "$wait" ] || wait=$(( (try+1) * 2 ))
      echo "[proj-sync] 429 rate-limited — ${wait}s 대기 후 재시도 ($((try+1))/$PS_SLACK_MAX_RETRY)" >&2
    elif [ "$code" -ge 500 ] 2>/dev/null || [ "$code" = "000" ]; then
      wait=$(( (try+1) * 2 ))
      echo "[proj-sync] HTTP $code — ${wait}s 대기 후 재시도 ($((try+1))/$PS_SLACK_MAX_RETRY)" >&2
    else
      rm -f "$hdr"
      # 정상 응답 뒤에도 최소 간격을 지켜 Tier 3 한도에 붙지 않게 한다
      sleep "$PS_SLACK_MIN_INTERVAL"
      return 0
    fi
    try=$((try+1))
    if [ "$try" -ge "$PS_SLACK_MAX_RETRY" ]; then
      rm -f "$hdr"
      echo "[proj-sync] 재시도 소진 — $url" >&2
      return 1
    fi
    sleep "$wait"
  done
}

# auth.test → ok 여부 + team/user 출력
ps_slack_auth_test() {
  ps_curl -s "https://slack.com/api/auth.test"
}

# auth.test 1회 호출로 헤더($1 파일)·바디($2 파일) 동시 저장 (왕복 1회로 인증+scope 점검)
ps_slack_auth_into() {
  ps_curl -s -D "$1" "https://slack.com/api/auth.test" -o "$2"
}

# 현재 봇 scope 문자열 반환 (x-oauth-scopes 헤더)
ps_slack_scopes() {
  ps_curl -s -D - \
    "https://slack.com/api/auth.test" -o /dev/null \
    | grep -i '^x-oauth-scopes' | sed 's/^[^:]*: *//' | tr -d '\r'
}

# 필수 scope 점검: 인자로 받은 scope 들이 모두 있는지. 없으면 누락 출력 + 1
ps_slack_require_scopes() {
  local have; have="$(ps_slack_scopes)"
  local missing=""
  for s in "$@"; do
    echo "$have" | tr ',' '\n' | grep -qx "$s" || missing="$missing $s"
  done
  if [ -n "$missing" ]; then
    echo "누락:$missing" >&2
    return 1
  fi
  return 0
}

# 채널 메시지 수집 (conversations.history) → JSON 배열을 stdout
# files.list 와 달리 cursor 기반 페이지네이션 (response_metadata.next_cursor)
# 인자: channel_id oldest_ts(Slack ts, 이 시각 이후만)
ps_slack_history() {
  local ch="$1" oldest="${2:-0}" cursor=""
  local acc resp; acc="$(mktemp)"; echo "[]" > "$acc"; resp="$(mktemp)"
  while :; do
    local url="https://slack.com/api/conversations.history?channel=$ch&limit=200&oldest=$oldest"
    [ -n "$cursor" ] && url="$url&cursor=$cursor"
    if ! ps_slack_get "$url" "$resp"; then
      rm -f "$acc" "$resp"; return 1
    fi
    cursor="$("$PS_PY" - "$acc" "$resp" <<'PY'
import json,sys
from urllib.parse import quote
acc=json.load(open(sys.argv[1]))
r=json.load(open(sys.argv[2]))
if not r.get('ok'):
    # 종전에는 경고만 찍고 루프를 빠져나가 '부분 수집'이 정상처럼 보였다.
    sys.stderr.write("[proj-sync] conversations.history 오류: %s\n" % r.get('error',''))
    sys.exit(3)
acc.extend(r.get('messages',[]))
json.dump(acc, open(sys.argv[1],'w',encoding='utf-8'), ensure_ascii=False)
nc=((r.get('response_metadata') or {}).get('next_cursor') or '') if r.get('has_more') else ''
print(quote(nc, safe=''))
PY
)" || { rm -f "$acc" "$resp"; return 1; }
    [ -n "$cursor" ] || break
  done
  cat "$acc"; rm -f "$acc" "$resp"
}

# 스레드 답글 수집 (conversations.replies) — 인자: channel_id thread_ts → JSON 배열
# 종전에는 limit=100 고정에 커서 처리가 없어 답글 100건을 넘으면 무경고로 잘렸고,
# 에러 체크가 없어 429 가 「답글 없음」으로 둔갑했다. history 와 동형으로 맞춘다.
ps_slack_replies() {
  local ch="$1" ts="$2" cursor=""
  local acc resp; acc="$(mktemp)"; echo "[]" > "$acc"; resp="$(mktemp)"
  while :; do
    local url="https://slack.com/api/conversations.replies?channel=$ch&ts=$ts&limit=200"
    [ -n "$cursor" ] && url="$url&cursor=$cursor"
    if ! ps_slack_get "$url" "$resp"; then
      rm -f "$acc" "$resp"; return 1
    fi
    cursor="$("$PS_PY" - "$acc" "$resp" <<'PY'
import json,sys
from urllib.parse import quote
acc=json.load(open(sys.argv[1]))
r=json.load(open(sys.argv[2]))
if not r.get('ok'):
    sys.stderr.write("[proj-sync] conversations.replies 오류: %s\n" % r.get('error',''))
    sys.exit(3)
acc.extend(r.get('messages',[]))
json.dump(acc, open(sys.argv[1],'w',encoding='utf-8'), ensure_ascii=False)
nc=((r.get('response_metadata') or {}).get('next_cursor') or '') if r.get('has_more') else ''
print(quote(nc, safe=''))
PY
)" || { rm -f "$acc" "$resp"; return 1; }
    [ -n "$cursor" ] || break
  done
  cat "$acc"; rm -f "$acc" "$resp"
}

# 텍스트 메시지 발신 (chat.postMessage). 인자: channel_id text [thread_ts] → 성공 시 "ok <ts>" 출력
# text 는 argv → python → JSON 직렬화로만 흐른다 (소스 보간 금지 — 인젝션 방지)
ps_slack_post_message() {
  local ch="$1" text="$2" thread="${3:-}"
  local payload resp rc; resp="$(mktemp)"
  payload="$("$PS_PY" - "$ch" "$text" "$thread" <<'PY'
import json,sys
d={"channel":sys.argv[1],"text":sys.argv[2]}
if sys.argv[3]: d["thread_ts"]=sys.argv[3]
# ensure_ascii=True: 페이로드를 순수 ASCII 로 만들어 어떤 로케일에서도 깨지지 않게 한다.
# \uXXXX 는 JSON 표준이라 Slack 이 원문 그대로 저장한다(문자수 한도에도 영향 없음).
print(json.dumps(d,ensure_ascii=True))
PY
)"
  ps_curl -s -X POST "https://slack.com/api/chat.postMessage" \
    -H "Content-Type: application/json; charset=utf-8" --data-binary "$payload" > "$resp"
  "$PS_PY" - "$resp" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if r.get('ok'): print("ok %s" % r.get('ts',''))
else:
    sys.stderr.write("[proj-sync] chat.postMessage 오류: %s\n" % r.get('error',''))
    if r.get('error')=='missing_scope':
        sys.stderr.write("  → 봇에 chat:write scope 필요: api.slack.com/apps → OAuth & Permissions → scope 추가 후 Reinstall to Workspace\n")
    sys.exit(1)
PY
  rc=$?; rm -f "$resp"; return $rc
}

# 메시지 1건 원문 조회. 인자: channel_id ts → 메시지 객체 JSON 을 stdout. 없으면 "null".
# 삭제·수정 전 사전조사용 — 무엇을 지우는지 보지 않고 지우지 않는다.
#
# ⚠️ conversations.history 만으로는 **스레드 답글을 찾지 못한다**(채널 최상위 메시지만 반환).
#    conversations.replies 는 ts 가 부모든 답글이든 그 스레드 전체를 돌려주므로 이쪽을 먼저 쓴다.
#    스레드가 아닌 최상위 메시지도 replies 가 자기 자신 1건으로 응답하지만,
#    응답이 비는 경우를 대비해 history 로 한 번 더 확인한다.
ps_slack_get_message() {
  local ch="$1" ts="$2" out resp thr
  thr="$(mktemp)"
  if ps_slack_replies "$ch" "$ts" > "$thr" 2>/dev/null; then
    out="$("$PS_PY" - "$thr" "$ts" <<'PY'
import json,sys
ms=json.load(open(sys.argv[1])) or []
hit=[m for m in ms if m.get("ts")==sys.argv[2]]
print(json.dumps(hit[0] if hit else None, ensure_ascii=True))
PY
)"
    if [ -n "$out" ] && [ "$out" != "null" ]; then
      rm -f "$thr"; printf '%s\n' "$out"; return 0
    fi
  fi
  rm -f "$thr"
  resp="$(mktemp)"
  ps_curl -s -G "https://slack.com/api/conversations.history" \
    --data-urlencode "channel=$ch" --data-urlencode "latest=$ts" \
    --data-urlencode "oldest=$ts" --data-urlencode "inclusive=true" \
    --data-urlencode "limit=1" > "$resp"
  "$PS_PY" - "$resp" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if not r.get('ok'):
    sys.stderr.write("[proj-sync] conversations.history 오류: %s\n" % r.get('error',''))
    sys.exit(1)
ms=r.get('messages') or []
print(json.dumps(ms[0] if ms else None, ensure_ascii=True))
PY
  local rc=$?; rm -f "$resp"; return $rc
}

# 메시지 삭제 (chat.delete). 인자: channel_id ts → 성공 시 "ok <ts>" 출력
# ⚠️ 되돌릴 수 없다. 첨부 파일 공유도 함께 사라진다. 호출 전 ps_slack_get_message 로 확인할 것.
# 봇 토큰은 **자기가 게시한 메시지만** 지울 수 있다(chat:write). 남의 메시지는 cant_delete_message.
ps_slack_delete() {
  local ch="$1" ts="$2"
  local payload resp rc; resp="$(mktemp)"
  payload="$("$PS_PY" - "$ch" "$ts" <<'PY'
import json,sys
print(json.dumps({"channel":sys.argv[1],"ts":sys.argv[2]},ensure_ascii=True))
PY
)"
  ps_curl -s -X POST "https://slack.com/api/chat.delete" \
    -H "Content-Type: application/json; charset=utf-8" --data-binary "$payload" > "$resp"
  "$PS_PY" - "$resp" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if r.get('ok'): print("ok %s" % r.get('ts',''))
else:
    e=r.get('error','')
    sys.stderr.write("[proj-sync] chat.delete 오류: %s\n" % e)
    hint={
      'cant_delete_message':"  → 봇이 게시하지 않은 메시지다. 작성자가 Slack UI 에서 지워야 한다\n",
      'message_not_found':"  → 해당 ts 의 메시지가 없다(이미 삭제됐거나 채널·ts 오기)\n",
      'missing_scope':"  → 봇에 chat:write scope 필요: api.slack.com/apps → OAuth & Permissions → scope 추가 후 Reinstall to Workspace\n",
      'channel_not_found':"  → 봇이 해당 채널 멤버가 아니다\n",
    }.get(e)
    if hint: sys.stderr.write(hint)
    sys.exit(1)
PY
  rc=$?; rm -f "$resp"; return $rc
}

# 채널 전 파일 메타 수집 (pagination) → JSON 배열을 stdout
# files.list 는 레거시 page 기반(paging.pages) 페이지네이션 사용 (cursor 미지원)
# 인자: channel_id
ps_slack_list_files() {
  local ch="$1" page=1 pages=1
  local acc; acc="$(mktemp)"; echo "[]" > "$acc"
  local resp; resp="$(mktemp)"
  while [ "$page" -le "$pages" ]; do
    ps_curl -s \
      "https://slack.com/api/files.list?channel=$ch&count=100&page=$page" > "$resp"
    pages="$("$PS_PY" - "$acc" "$resp" <<'PY'
import json,sys
acc=json.load(open(sys.argv[1]))
r=json.load(open(sys.argv[2]))
if not r.get('ok'):
    sys.stderr.write("[proj-sync] files.list 오류: %s\n" % r.get('error',''))
acc.extend(r.get('files',[]))
json.dump(acc, open(sys.argv[1],'w',encoding='utf-8'), ensure_ascii=False)
print((r.get('paging') or {}).get('pages',1))
PY
)"
    page=$((page+1))
  done
  cat "$acc"
  rm -f "$acc" "$resp"
}
