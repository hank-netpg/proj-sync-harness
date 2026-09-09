#!/usr/bin/env bash
# proj-sync: Slack 텍스트 메시지 발신 (chat.postMessage — slack_upload.sh 는 파일 전용)
# 사용: slack_post.sh [채널ID] [--thread <ts>] <메시지...>
#   채널 미지정 시 config.slack.channel_id. 메시지의 @이름 → config.mentions 역매핑으로 <@UID> 확장.
#   필요 scope: chat:write (없으면 오류 메시지에 Reinstall 안내 출력)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
. "$HERE/lib/slack_api.sh"

ps_load_config || exit 1
PS_SLACK_TOKEN="$(ps_slack_token)"; ps_slack_init_token || exit 1

CH="$(ps_cfg '.slack.channel_id')"
THREAD=""
# 채널 인자는 'C...' 형태일 때만 인식 (slack_upload.sh 와 동일 규칙)
if [ $# -ge 1 ] && printf '%s' "$1" | grep -qE '^C[A-Z0-9]{6,}$'; then
  CH="$1"; shift
fi
if [ "${1:-}" = "--thread" ]; then
  THREAD="${2:?--thread 뒤에 ts 필요}"; shift 2
fi
MSG="${*:?사용: slack_post.sh [채널ID] [--thread ts] <메시지>}"
[ -n "$CH" ] || { echo "[slack-post] ✗ 채널 미지정 (config.slack.channel_id 또는 인자)" >&2; exit 1; }

# 멘션 확장: @이름 → <@UID> (MSG 는 argv 전달 — 소스 보간 금지)
MSG="$("$PS_PY" - "$PS_CONFIG" "$MSG" <<'PY'
import json,sys
cfg=json.load(open(sys.argv[1],encoding='utf-8')); msg=sys.argv[2]
# 긴 이름부터 치환해 부분문자열 충돌 방지 (예: "@김민" vs "@김민수")
for uid,nm in sorted((cfg.get('mentions') or {}).items(), key=lambda kv: -len(kv[1])):
    msg=msg.replace(f"@{nm}", f"<@{uid}>")
# print() 는 sys.stdout.encoding(=로케일) 으로 인코딩한다 — 한국어 Windows 에서 cp949 가 되어
# 여기서 이미 한글이 깨진 채 다음 단계로 넘어갔다. 바이트를 직접 써서 로케일을 우회한다.
sys.stdout.buffer.write(msg.encode('utf-8'))
PY
)"

if OUT="$(ps_slack_post_message "$CH" "$MSG" "$THREAD")"; then
  echo "[slack-post] ✓ 발신 완료 (ts=${OUT#ok })"
else
  echo "[slack-post] ✗ 발신 실패 — 위 오류 참고" >&2
  exit 1
fi
