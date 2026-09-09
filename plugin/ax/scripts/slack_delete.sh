#!/usr/bin/env bash
# proj-sync: Slack 메시지 회수 (chat.delete) — 기본은 조회만, 삭제는 --yes 필요
# 사용: slack_delete.sh [채널ID] <ts> [--yes]
#   채널 미지정 시 config.slack.channel_id. ts 는 '1785811080.185219' 형식.
#   필요 scope: chat:write
#
# ── 원칙: 남의 메시지는 건드리지 않는다 ─────────────────────────
# **사람이 쓴 메시지는 삭제·수정하지 않는다.** 이 스크립트가 지울 수 있는 것은
# **이 봇이 직접 게시한 메시지뿐**이며, 그 외(사람·타 앱 봇)는 조회 단계에서 차단한다.
# 남의 말을 지우거나 고치는 것은 대화 기록을 위조하는 일이다 — 정정이 필요하면
# 본인에게 알리거나 정정 메시지를 덧붙인다.
#
# 왜 2단계인가 — 삭제는 되돌릴 수 없고 **첨부 파일 공유까지 함께 사라진다**.
#   1) 인자만 주면: 대상 메시지의 작성자·시각·본문·첨부·리액션·답글을 출력하고 **삭제하지 않는다**.
#   2) --yes 를 붙이면: 위 사전조사를 출력한 뒤 실제로 삭제한다.
# 회수 전 확인할 것 — 상대가 이미 회신했는가 · 그 메시지가 요청한 자료가 있는가 ·
#   제3자에게 전달됐는가. 하나라도 해당하면 지우지 말고 정정 메시지를 덧붙이는 편이 낫다.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
. "$HERE/lib/slack_api.sh"

USAGE='사용: slack_delete.sh [채널ID] <ts> [--yes]'
ps_load_config || exit 1
PS_SLACK_TOKEN="$(ps_slack_token)"; ps_slack_init_token || exit 1

CH="$(ps_cfg '.slack.channel_id')"
# 채널 인자는 'C...' 형태일 때만 인식 (slack_post.sh·slack_upload.sh 와 동일 규칙)
if [ $# -ge 1 ] && printf '%s' "$1" | grep -qE '^C[A-Z0-9]{6,}$'; then
  CH="$1"; shift
fi
TS="${1:-}"; shift || true
YES=0
[ "${1:-}" = "--yes" ] && YES=1
[ -n "$CH" ] || { echo "[slack-delete] ✗ 채널 미지정 (config.slack.channel_id 또는 인자)" >&2; exit 1; }
printf '%s' "$TS" | grep -qE '^[0-9]{10}\.[0-9]{6}$' \
  || { echo "[slack-delete] ✗ ts 형식 오류: '${TS}' — $USAGE" >&2; exit 1; }

# ── 1) 사전조사 ──────────────────────────────────────────────
# 우리 봇의 bot_id — 대상이 '이 봇이 쓴 메시지'인지 대조하는 데 쓴다.
# auth.test 는 봇 토큰이면 bot_id 를 돌려준다. 못 얻으면 빈 값이고, 그때는 소유 확인이
# 불가능하므로 삭제를 막는다(모르면 지우지 않는다).
MY_BOT_ID="$(ps_slack_auth_test | "$PS_PY" -c 'import json,sys; print((json.load(sys.stdin) or {}).get("bot_id") or "")' 2>/dev/null || true)"

MSG="$(ps_slack_get_message "$CH" "$TS")" || exit 1
BLOCKED="$("$PS_PY" - "$MSG" "$TS" "$MY_BOT_ID" <<'PY'
import json,sys,datetime
m=json.loads(sys.argv[1]); ts=sys.argv[2]; mybot=sys.argv[3]
if m is None:
    sys.stderr.write("[slack-delete] ✗ 해당 ts 의 메시지가 없습니다 (이미 삭제됐거나 채널·ts 오기)\n")
    sys.exit(2)
when=datetime.datetime.fromtimestamp(float(m['ts'])).strftime('%Y-%m-%d %H:%M:%S')
who=m.get('bot_id') and ('봇 %s' % m['bot_id']) or ('사용자 %s' % m.get('user',''))
files=[f.get('name','?') for f in (m.get('files') or [])]
reacts=[('%s×%d' % (r.get('name'), r.get('count',0))) for r in (m.get('reactions') or [])]
text=(m.get('text') or '').replace('\n',' ⏎ ')
print("── 삭제 대상 ─────────────────────────────")
print("  ts       : %s (%s)" % (ts, when))
print("  작성     : %s" % who)
print("  본문     : %s%s" % (text[:200], '…' if len(text)>200 else ''))
print("  첨부     : %s" % (' · '.join(files) if files else '없음'))
print("  리액션   : %s" % (' · '.join(reacts) if reacts else '없음'))
print("  스레드   : parent=%s replies=%s" % (m.get('thread_ts','-'), m.get('reply_count',0)))
print("──────────────────────────────────────────")
# ── 소유 확인: 이 봇이 쓴 메시지가 아니면 지우지 않는다(원칙) ──
if not m.get('bot_id'):
    print("BLOCK 사람이 쓴 메시지입니다 — 원칙상 남의 메시지는 삭제·수정하지 않습니다. "
          "정정이 필요하면 작성자에게 알리거나 정정 메시지를 덧붙이세요")
    sys.exit(0)
if not mybot:
    print("BLOCK 이 봇의 bot_id 를 확인하지 못했습니다(auth.test) — 소유를 확인할 수 없으면 지우지 않습니다")
    sys.exit(0)
if m['bot_id'] != mybot:
    print("BLOCK 다른 앱(%s)이 게시한 메시지입니다 — 이 봇(%s)이 쓴 메시지만 지울 수 있습니다"
          % (m['bot_id'], mybot))
    sys.exit(0)
# 스레드 부모 삭제는 답글을 고아로 만든다 → 차단
if m.get('thread_ts')==ts and (m.get('reply_count') or 0)>0:
    print("BLOCK 스레드 부모(답글 %d건) — 지우면 답글이 고아가 됩니다. 답글부터 정리하세요" % m['reply_count'])
    sys.exit(0)
warn=[]
if files: warn.append("첨부 %d건이 함께 사라집니다" % len(files))
if reacts: warn.append("리액션이 있습니다 — 이미 읽혔을 가능성")
for w in warn: print("  ⚠ %s" % w)
print("OK")
PY
)" || { rc=$?; [ "$rc" = "2" ] && exit 1 || exit $rc; }

echo "$BLOCKED" | grep -v '^BLOCK \|^OK$' || true
if printf '%s' "$BLOCKED" | grep -q '^BLOCK '; then
  echo "[slack-delete] ✗ $(printf '%s' "$BLOCKED" | sed -n 's/^BLOCK //p')" >&2
  exit 1
fi

if [ "$YES" -ne 1 ]; then
  echo "[slack-delete] 조회만 했습니다 — 실제로 지우려면 --yes 를 붙이세요"
  echo "  bash \"$0\" $CH $TS --yes"
  exit 0
fi

# ── 2) 삭제 ─────────────────────────────────────────────────
if OUT="$(ps_slack_delete "$CH" "$TS")"; then
  echo "[slack-delete] ✓ 삭제 완료 (ts=${OUT#ok })"
  echo "  ※ 되돌릴 수 없습니다. 대체 메시지가 필요하면 slack_post.sh / slack_upload.sh 로 다시 올리세요."
else
  echo "[slack-delete] ✗ 삭제 실패 — 위 오류 참고" >&2
  exit 1
fi
