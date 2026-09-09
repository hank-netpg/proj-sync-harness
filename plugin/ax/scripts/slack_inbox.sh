#!/usr/bin/env bash
# proj-sync: Slack 인바운드 폴링 — 채널 메시지를 커서 기준으로 수집·플래그 부여 (읽기 전용)
#   상주 서버(Events API) 없이 폴링으로 반자동 수신. 결과 JSON 을 에이전트(inbox 스킬)가 트리아지한다.
#   이 스크립트는 결정론적 수집·필터만 담당 — 메시지 본문을 해석·실행하지 않는다(비신뢰 입력).
# 사용:
#   slack_inbox.sh poll [--dry-run] [--threads|--all-threads] [--oldest TS] [--archive DIR] [--no-bots]
#       --dry-run     : 커서(state) 미갱신 — 미리보기용 (VSCode 태스크 등)
#       --threads     : 액션 후보(멘션/키워드) 메시지의 스레드 답글만 수집
#       --all-threads : reply_count>0 인 **모든** 스레드 답글 수집 (전수조사용)
#       --oldest TS   : 커서를 무시하고 이 시각부터 수집. 0 이면 채널 개설 이후 전기간
#       --archive DIR : 메시지·답글을 DIR/<channel>.jsonl 로 영속화(ts 기준 멱등 병합)
#       --no-bots     : 봇 메시지 제외. 기본은 **포함**(자기 메시지 포함) —
#                       이 도구로 공유한 산출물이 폴링에서 빠지면 사람이 "새 메시지 없음"으로
#                       오인한다. 각 메시지에 is_bot / is_self 플래그가 붙는다.
#   slack_inbox.sh state                          # 현재 커서 상태 출력
# 상태 파일: .proj-sync/slack-inbox-state.json (개인 커서 — gitignore 대상)
# 키워드: config.slack.inbox_keywords (JSON 배열, 없으면 기본셋)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
. "$HERE/lib/slack_api.sh"
set +e   # config.sh 의 set -e 복원 — 수집 실패는 메시지로 처리

CMD="${1:-poll}"; shift 2>/dev/null || true
DRY=0; THREADS=0; ALL_THREADS=0; OLDEST_OVERRIDE=""; ARCHIVE_DIR=""; NOBOTS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --threads) THREADS=1 ;;
    --all-threads) THREADS=1; ALL_THREADS=1 ;;
    --no-bots) NOBOTS=1 ;;
    --oldest) shift; OLDEST_OVERRIDE="${1:-}" ;;
    --archive) shift; ARCHIVE_DIR="${1:-}" ;;
  esac
  shift 2>/dev/null || break
done

ps_load_config || exit 1
STATE="$PS_ROOT/.proj-sync/slack-inbox-state.json"

# state 는 커서 파일만 읽음 — 토큰 불필요 (오프라인 점검 가능)
if [ "$CMD" = "state" ]; then
  if [ -f "$STATE" ]; then cat "$STATE"; else echo '{"version":1,"channels":{}}'; fi
  exit 0
fi
[ "$CMD" = "poll" ] || { echo "사용: slack_inbox.sh poll [--dry-run] [--threads|--all-threads] [--no-bots] | state" >&2; exit 1; }

PS_SLACK_TOKEN="$(ps_slack_token)"; ps_slack_init_token || exit 1

CH="$(ps_cfg '.slack.channel_id')"
[ -n "$CH" ] || { echo "[inbox] ✗ config.slack.channel_id 미설정" >&2; exit 1; }

# ── 봇 자신의 user_id (state 캐시 → 없으면 auth.test 1회) ──
BOT_UID=""
[ -f "$STATE" ] && BOT_UID="$("$PS_PY" -c "import json,sys;print((json.load(open(sys.argv[1])).get('bot_user_id') or ''))" "$STATE" 2>/dev/null)"
if [ -z "$BOT_UID" ]; then
  BOT_UID="$(ps_slack_auth_test | "$PS_PY" -c "import json,sys;print(json.load(sys.stdin).get('user_id',''))")"
fi

# ── 커서(oldest) 결정: state.last_ts → 없으면 최근 24h ──
OLDEST="$("$PS_PY" - "$STATE" "$CH" <<'PY'
import json,sys,time,os
state_p, ch = sys.argv[1], sys.argv[2]
last=""
if os.path.exists(state_p):
    try: last=(json.load(open(state_p)).get('channels') or {}).get(ch,{}).get('last_ts','')
    except Exception: last=""
print(last if last else "%.6f" % (time.time()-86400))
PY
)"

# --oldest 로 커서를 덮어쓴다(전기간 baseline 수집용). 0 이면 채널 개설 이후 전량.
if [ -n "$OLDEST_OVERRIDE" ]; then
  OLDEST="$OLDEST_OVERRIDE"
  echo "[inbox] --oldest $OLDEST (커서 무시)" >&2
fi

# ── 수집 (cursor 페이지네이션) ──
# 수집 실패를 성공으로 넘기지 않는다 — 부분 수집이 정상처럼 보이면 그 위에 쌓는
# 모든 판단이 틀린다. 종전에는 429 가 조용한 빈 결과로 나타났다.
RAW="$(mktemp)"
if ! ps_slack_history "$CH" "$OLDEST" > "$RAW"; then
  echo "[inbox] ✗ 메시지 수집 실패 (채널 $CH) — 커서를 갱신하지 않고 중단" >&2
  rm -f "$RAW"; exit 2
fi

# ── 키워드(config 재정의 가능) ──
KEYWORDS="$(ps_cfg '.slack.inbox_keywords' 2>/dev/null)"

# ── 필터·플래그 부여 + 신규 커서 산출 (결정론적 — 본문 해석 없음) ──
OUT="$(mktemp)"; NEWSTATE="$(mktemp)"
"$PS_PY" - "$RAW" "$BOT_UID" "$KEYWORDS" "$STATE" "$CH" "$OLDEST" "$NOBOTS" <<'PY' > "$OUT" 3> "$NEWSTATE"
import json, sys, re, os
raw_p, bot_uid, kw_json, state_p, ch, oldest = sys.argv[1:7]
no_bots = (len(sys.argv) > 7 and sys.argv[7] == "1")
msgs = json.load(open(raw_p))
try:
    kws = json.loads(kw_json) if kw_json else []
except Exception:
    kws = []
if not kws:
    kws = ["요청","검토","부탁","초안","승인","확인","마감","자료","해줘"]
kw_re = re.compile("|".join(re.escape(k) for k in kws) + r"|\?\s*$")

out=[]; max_ts=oldest
for m in msgs:
    ts=m.get("ts","")
    if ts and float(ts) > float(max_ts): max_ts=ts
    # 봇/자신 메시지 처리 — 기본 포함.
    #   이 도구(봇 토큰)로 보낸 메시지에는 **산출물 공유가 포함**된다. 이를 제외하면
    #   정작 중요한 파일 공유가 폴링에서 통째로 누락돼, 사람이 "새 메시지 없음"으로 오인한다.
    #   자기 메시지는 is_self 로 표시만 하고, 제외는 --no-bots 를 준 경우에만.
    u=m.get("user","")
    is_self = bool(bot_uid) and u==bot_uid
    is_bot  = is_self or (m.get("subtype")=="bot_message") or bool(m.get("bot_id"))
    if no_bots and is_bot: continue
    text=m.get("text","") or ""
    out.append({
        "ts": ts,
        "thread_ts": m.get("thread_ts",""),
        "user": u,
        "text": text,
        "is_bot": is_bot,
        "is_self": is_self,
        "mentions_bot": bool(bot_uid) and (f"<@{bot_uid}>" in text),
        "keyword_hit": bool(kw_re.search(text)),
        "has_files": bool(m.get("files")),
        "reply_count": m.get("reply_count",0),
    })
out.sort(key=lambda x: x["ts"])                   # 오래된 것부터
json.dump({"channel": ch, "oldest": oldest, "count": len(out), "messages": out},
          sys.stdout, ensure_ascii=False, indent=1)

# 신규 state (fd 3)
state={"version":1,"channels":{}}
if os.path.exists(state_p):
    try: state=json.load(open(state_p))
    except Exception: pass
state.setdefault("channels",{})[ch]={"last_ts": max_ts}
state["bot_user_id"]=bot_uid
json.dump(state, os.fdopen(3,"w"), ensure_ascii=False)
PY

# ── 스레드 보강 ──
# --threads      : 액션 후보(멘션/키워드)만 — 일상 폴링용
# --all-threads  : reply_count>0 전수 — 전수조사용. 종전에는 이 모드가 없어
#                  키워드에 안 걸린 스레드의 논의를 통째로 놓쳤다.
if [ "$THREADS" = 1 ]; then
  TS_LIST="$("$PS_PY" -c "
import json,sys
d=json.load(open(sys.argv[1])); allmode = sys.argv[2] == '1'
for m in d['messages']:
    if not m['reply_count']: continue
    if allmode or m['mentions_bot'] or m['keyword_hit']:
        print(m['ts'])" "$OUT" "$ALL_THREADS")"
  if [ -n "$TS_LIST" ]; then
    TH="$(mktemp)"; echo "{}" > "$TH"; TH_FAIL=0
    while IFS= read -r ts; do
      [ -n "$ts" ] || continue
      if ! ps_slack_replies "$CH" "$ts" | "$PS_PY" -c "
import json,sys
th=json.load(open(sys.argv[1])); th[sys.argv[2]]=json.load(sys.stdin)
json.dump(th, open(sys.argv[1],'w'), ensure_ascii=False)" "$TH" "$ts"; then
        TH_FAIL=$((TH_FAIL+1))
        echo "[inbox] ✗ 스레드 수집 실패 ts=$ts" >&2
      fi
    done <<< "$TS_LIST"
    if [ "$TH_FAIL" -gt 0 ]; then
      echo "[inbox] ✗ 스레드 $TH_FAIL 건 실패 — 커서를 갱신하지 않고 중단" >&2
      rm -f "$RAW" "$OUT" "$NEWSTATE" "$TH"; exit 2
    fi
    "$PS_PY" -c "
import json,sys
d=json.load(open(sys.argv[1])); d['threads']=json.load(open(sys.argv[2]))
json.dump(d, open(sys.argv[1],'w'), ensure_ascii=False, indent=1)" "$OUT" "$TH"
    rm -f "$TH"
  fi
fi

# ── 아카이브 (--archive) ──
# 종전에는 결과가 stdout 뿐이라 휘발됐다. 매 조사마다 API 를 새로 때려야 했고,
# 과거 논의를 되짚을 원본이 남지 않았다. ts 를 키로 멱등 병합해 재수집해도
# 중복되지 않게 한다(전기간 baseline 을 다시 돌려도 안전).
if [ -n "$ARCHIVE_DIR" ]; then
  mkdir -p "$ARCHIVE_DIR"
  "$PS_PY" - "$OUT" "$ARCHIVE_DIR/$CH.jsonl" <<'PY' >&2
import json, os, sys
out_p, arch_p = sys.argv[1], sys.argv[2]
d = json.load(open(out_p))
seen = {}
if os.path.exists(arch_p):
    with open(arch_p, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                m = json.loads(line)
            except Exception:
                continue          # 손상 행은 버리고 재수집분으로 대체
            seen[m.get("ts", "")] = m

before = len(seen)
for m in d.get("messages", []):
    seen[m["ts"]] = m
# 스레드 답글도 같은 평면에 담는다 — thread_ts 로 부모와 연결된다
for parent_ts, replies in (d.get("threads") or {}).items():
    for r in replies:
        ts = r.get("ts", "")
        if not ts or ts == parent_ts:
            continue              # 부모 메시지는 이미 messages 에 있다
        seen[ts] = {"ts": ts, "thread_ts": r.get("thread_ts", parent_ts),
                    "user": r.get("user", ""), "text": r.get("text", "") or "",
                    "has_files": bool(r.get("files")), "is_reply": True}

with open(arch_p, "w", encoding="utf-8") as f:
    for ts in sorted(seen, key=lambda x: float(x) if x else 0.0):
        f.write(json.dumps(seen[ts], ensure_ascii=False) + "\n")
print(f"[inbox] 아카이브 {arch_p} — 총 {len(seen)}건 (신규 {len(seen)-before})")
PY
fi

cat "$OUT"; echo

# ── 커서 갱신 (--dry-run 은 미갱신) ──
if [ "$DRY" = 0 ]; then
  mkdir -p "$(dirname "$STATE")"
  cp "$NEWSTATE" "$STATE"
  echo "[inbox] 커서 갱신: $STATE" >&2
else
  echo "[inbox] --dry-run — 커서 미갱신" >&2
fi
rm -f "$RAW" "$OUT" "$NEWSTATE"
