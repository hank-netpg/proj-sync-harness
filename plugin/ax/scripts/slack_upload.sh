#!/usr/bin/env bash
# proj-sync: Slack 파일 업로드 (getUploadURLExternal → PUT → completeUploadExternal)
# 사용: slack_upload.sh <파일경로...> [채널ID] [--thread <ts>] [메시지...]
#   채널 미지정 시 config.slack.channel_id 사용. 메시지에 @이름 → config.mentions 역매핑으로 <@UID> 확장
#   --thread 지정 시 해당 스레드에 첨부 (slack_post.sh 와 동일 인자 규약)
#   파일을 여러 개 주면 한 메시지에 모두 첨부됨 — 파일마다 메시지가 쪼개지지 않음
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
. "$HERE/lib/slack_api.sh"

USAGE='사용: slack_upload.sh <파일경로...> [채널ID] [--thread ts] [메시지]'
# 선행 인자 중 실제 존재하는 파일을 모두 수집 (그 뒤 토큰은 채널/스레드/메시지)
FILES=()
while [ $# -ge 1 ] && [ -f "$1" ]; do FILES+=("$1"); shift; done
[ ${#FILES[@]} -ge 1 ] || { echo "[proj-sync] ✗ 업로드할 파일 없음 — $USAGE" >&2; exit 1; }

ps_load_config || exit 1
PS_SLACK_TOKEN="$(ps_slack_token)"; ps_slack_init_token || exit 1

# 채널 인자는 'C...' 형태일 때만 인식 (그 외 토큰은 메시지로 처리)
CH="$(ps_cfg '.slack.channel_id')"
THREAD=""
if [ $# -ge 1 ] && printf '%s' "$1" | grep -qE '^C[A-Z0-9]{6,}$'; then
  CH="$1"; shift
fi
if [ "${1:-}" = "--thread" ]; then
  THREAD="${2:?--thread 뒤에 ts 필요}"; shift 2
fi
MSG="${*:-}"
[ -n "$CH" ] || { echo "[proj-sync] ✗ 채널 미지정 (config.slack.channel_id 또는 인자)" >&2; exit 1; }

# 1~2) 파일별로 업로드 URL 발급 후 바이트 전송 — file_id 를 모아 둔다
IDS=()
for F in "${FILES[@]}"; do
  NAME="$(basename "$F")"
  SIZE="$(stat -f%z "$F" 2>/dev/null || stat -c%s "$F")"
  R1="$(ps_curl -s \
    --data-urlencode "filename=$NAME" --data-urlencode "length=$SIZE" \
    "https://slack.com/api/files.getUploadURLExternal")"
  UURL="$(echo "$R1" | "$PS_PY" -c "import json,sys;print(json.load(sys.stdin).get('upload_url',''))")"
  FID="$(echo "$R1"  | "$PS_PY" -c "import json,sys;print(json.load(sys.stdin).get('file_id',''))")"
  [ -z "$UURL" ] && { echo "[proj-sync] ✗ 업로드 URL 발급 실패($NAME): $R1" >&2; exit 1; }
  HTTP="$(curl -s -o /dev/null -w "%{http_code}" -F "file=@$F" "$UURL")"
  [ "$HTTP" = "200" ] || { echo "[proj-sync] ✗ 업로드 실패($NAME) HTTP $HTTP" >&2; exit 1; }
  IDS+=("$FID:$NAME")
  echo "[proj-sync]   ↑ $NAME ($((SIZE/1024))KB)"
done

# 3) 완료 게시 — 수집한 file_id 전부를 한 메시지로 (멘션 확장: @이름 → <@UID>)
#    MSG·파일목록은 소스 보간이 아닌 argv 로 전달 (인젝션 방지)
PAYLOAD="$("$PS_PY" - "$CH" "$PS_CONFIG" "$MSG" "$THREAD" "${IDS[@]}" <<'PY'
import json,sys
ch,cfgp,msg,thread = sys.argv[1:5]
cfg=json.load(open(cfgp))
# config.mentions = {UID: 이름} → 이름으로 <@UID> 치환
# 긴 이름부터 치환해 부분문자열 충돌 방지 (예: "@김민" vs "@김민수")
for uid,nm in sorted((cfg.get('mentions') or {}).items(), key=lambda kv: -len(kv[1])):
    msg=msg.replace(f"@{nm}", f"<@{uid}>")
files=[]
for tok in sys.argv[5:]:
    fid,_,name = tok.partition(':')      # file_id 에는 ':' 가 없음
    files.append({"id":fid,"title":name})
d={"files":files,"channel_id":ch,"initial_comment":msg}
if thread: d["thread_ts"]=thread   # 지정 시 스레드에 첨부
# ensure_ascii=True: 로케일과 무관하게 순수 ASCII 로 전송 (한국어 Windows cp949 대응)
print(json.dumps(d, ensure_ascii=True))
PY
)"
RESP="$(ps_curl -s -X POST "https://slack.com/api/files.completeUploadExternal" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data-binary "$PAYLOAD")"
echo "$RESP" | "$PS_PY" -c "import json,sys;d=json.load(sys.stdin);print('[proj-sync] 업로드',('성공' if d.get('ok') else '실패'),d.get('error',''));[print('  file:',f.get('name'),f.get('id')) for f in d.get('files',[])]"
