#!/usr/bin/env bash
# proj-sync: 프리플라이트 — Python/gh/Git LFS/Slack/config 점검 (비개발자 친화 진단)
# 모든 ✗ 에 복붙용 해결 명령을 함께 출력. 종료코드 0=정상, 1=문제.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
. "$HERE/lib/version_check.sh"
. "$HERE/lib/slack_api.sh"
set +e   # 점검은 실패해도 끝까지 진행 (config.sh의 set -e 누수 복원)

# 셔임 생성·갱신 (~/.proj-sync/bin/ax) — VSCode tasks 가 이 경로를 호출. doctor 가 자주 돌므로 여기서 최신화.
ps_write_shim 2>/dev/null || true

OK=0; FAIL=0
ok(){ printf '  \xe2\x9c\x93 %s\n' "$1"; OK=$((OK+1)); }
ng(){ printf '  \xe2\x9c\x97 %s\n' "$1"; FAIL=$((FAIL+1)); }
fix(){ printf '       \xe2\x86\xb3 %s\n' "$1"; }   # 해결 방법(복붙용)

# OS별 설치 안내
case "$(uname -s)" in
  Darwin)              OS=mac;   LFS_FIX="brew install git-lfs";              PY_FIX="brew install python" ;;
  MINGW*|MSYS*|CYGWIN*) OS=win;  LFS_FIX="https://git-lfs.github.com 에서 설치"; PY_FIX="https://python.org 에서 설치 후 PATH 등록" ;;
  *)                   OS=linux; LFS_FIX="sudo apt install git-lfs (또는 배포판 패키지)"; PY_FIX="sudo apt install python3" ;;
esac

echo "=== proj-sync doctor ==="

# 0) config (없으면 더 진행 불가)
if ps_load_config; then
  PID="$(ps_cfg '.project.id')"
  ok "config: $PS_CONFIG${PID:+  (project=$PID)}"
else
  ng "설정 파일 없음 (.proj-sync/config.json)"
  fix "이 사업 폴더에서 /ax:init 을 먼저 실행하세요."
  echo "------------------------------------"; echo "결과: ✓ 0 / ✗ 1"; exit 1
fi

# 0.05) additive 마이그레이션 — **재init 없이** 플러그인 개선을 이 사업에 닿게 한다(issue #16).
#   doctor 는 run-sync 0단계라 사실상 모든 동기화에서 돈다. 이미 ps_write_shim 으로 같은 성격의
#   자기 갱신을 하고 있다(위). 없는 것만 추가하므로 반복 실행이 안전하다 — 바꾼 게 있으면 반드시 출력한다.
#   끄려면 PS_NO_MIGRATE=1.
bash "$HERE/config_migrate.sh" || true

# 0.1) config 를 만든 사본 ↔ 지금 도는 사본 — 낡은 사본으로 init 하면 스캐폴드가 통째로 빠지는데,
#   종전에는 산출물에 버전이 없어 사후에 알 방법이 없었다(2026-08-07 실측, issue #14).
#   ✗(FAIL)로 세지 않는다 — 릴리즈마다 전 사업이 빨간불이 되면 ✗ 의 「지금 막힌 문제」 의미가 흐려진다.
RUN_VER="$(ps_plugin_version)"
CFG_VER="$(ps_cfg '._init.plugin_version' 2>/dev/null || true)"
if [ -z "$CFG_VER" ] || [ "$CFG_VER" = "null" ]; then
  printf '  \xe2\x84\xb9 init 버전 미기록 (v1.14.0 이하로 만든 config) — 지금 도는 사본은 v%s\n' "$RUN_VER"
  printf '       \xe2\x86\xb3 스캐폴드 누락이 의심되면 재init:  PS_FORCE=1 bash "%s/scripts/init.sh"\n' "$(ps_plugin_root)"
elif [ "$CFG_VER" = "$RUN_VER" ]; then
  ok "init 버전: v$CFG_VER (지금 도는 사본과 동일)"
elif [ "$(printf '%s\n%s\n' "$CFG_VER" "$RUN_VER" | sort -V | head -1)" = "$CFG_VER" ]; then
  printf '  \xe2\x84\xb9 init 버전: config=v%s < 실행 v%s — 이후 추가된 스캐폴드·기본값이 없을 수 있습니다\n' "$CFG_VER" "$RUN_VER"
  printf '       \xe2\x86\xb3 재init(기존 설정 보존):  PS_FORCE=1 bash "%s/scripts/init.sh"\n' "$(ps_plugin_root)"
else
  printf '  \xe2\x84\xb9 init 버전: config=v%s > 실행 v%s — 낡은 사본으로 돌고 있을 수 있습니다 (사본: %s)\n' \
    "$CFG_VER" "$RUN_VER" "$(ps_plugin_root)"
fi

# 0.2) 도는 사본 ↔ 릴리즈 최신 버전 — 0.1 은 "config vs 사본"만 봐서, **사본 자체가 낡은 경우**는
#   여전히 안 보였다(issue #14 가 실제로 당한 상황: 0.1.0 사본으로 init). 릴리즈와 대조해 드러낸다.
#   네트워크·gh 인증이 없으면 조용히 건너뛴다(진단 자체를 막지 않는다).
#
#   판정은 lib/version_check.sh 가 한다 — SessionStart 훅(issue #18)이 같은 판정을 쓰기 때문이다.
#   TTL=0: 진단은 캐시를 쓰지 않고 항상 실측한다. 캐시는 세션마다 도는 훅 쪽 사정이다.
LATEST_VER="$(ps_latest_release_version 0)"
case "$(ps_version_state "$RUN_VER" "$LATEST_VER")" in
  outdated)
    printf '  \xe2\x84\xb9 플러그인 사본이 낡았습니다: 실행 v%s < 최신 v%s\n' "$RUN_VER" "$LATEST_VER"
    printf '       \xe2\x86\xb3 업데이트:  claude plugin update ax@ax-harness   (사본: %s)\n' "$(ps_plugin_root)" ;;
  current)
    ok "플러그인: v$RUN_VER (릴리즈 최신)" ;;
  ahead)
    # 실행 > 릴리즈 — 개발 사본(아직 태그 전)이다. "최신"이라고 말하면 거짓이 된다.
    printf '  \xe2\x84\xb9 플러그인: 실행 v%s > 릴리즈 v%s — 미배포(개발) 사본입니다\n' "$RUN_VER" "$LATEST_VER" ;;
  *) : ;;   # unknown — gh 미설치·미인증·오프라인. 조용히 넘어간다.
esac

# 0.5) Python
if [ -n "$PS_PY" ]; then ok "Python: $("$PS_PY" --version 2>&1 | head -1) ($PS_PY)"
else ng "Python 미설치"; fix "$PY_FIX"; fi

# 0.6) Python stdio 인코딩 — 여기가 UTF-8 이 아니면 Slack·Notion 에 **한글이 깨진 채 발신된다.**
#   스크립트들이 페이로드를 `python … | $(...)` 로 만드는데, print() 는 sys.stdout.encoding
#   (= 로케일 기본) 으로 인코딩한다. 한국어 Windows 는 cp949 라 그 바이트가 charset=utf-8 로
#   전송돼 "동기화 완료" 가 "????ȭ ?Ϸ?" 가 됐다(2026-08-26 실측, 2개 사업 채널).
#
#   config.sh 가 PYTHONUTF8·PYTHONIOENCODING 을 export 해 막는다. 그래서 **실효값만 보면
#   언제나 utf-8 이라 점검이 아무것도 잡지 못한다** — 두 값을 따로 잰다:
#     NATIVE = 두 환경변수를 걷어낸 이 PC 의 맨 로케일 (env -u)
#     EFF    = 지금 실제로 쓰이는 값
#   EFF 가 UTF-8 이 아니면 ✗(막이 뚫렸다). NATIVE 만 다르면 ℹ — 정상이지만 **왜 정상인지**를
#   알려준다. 조용히 깨지는 결함이라 사후에 알 방법이 없었던 것이 이 문제의 본질이었다.
if [ -n "$PS_PY" ]; then
  PYENC_EFF="$("$PS_PY" -c 'import sys;print(sys.stdout.encoding)' 2>/dev/null | tr -d '\r')"
  PYENC_NATIVE="$(env -u PYTHONUTF8 -u PYTHONIOENCODING "$PS_PY" -c 'import sys;print(sys.stdout.encoding)' 2>/dev/null | tr -d '\r')"
  # sed 로 지운다 — BSD tr 은 `-d '-_'` 의 선두 '-' 를 옵션으로 읽어 실패한다.
  _lc() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/[-_]//g'; }
  case "$(_lc "$PYENC_EFF")" in
    utf8)
      ok "Python stdout 인코딩: $PYENC_EFF"
      # ✗ 로 세지 않는다 — 지금 막힌 문제가 아니다(0.2 절·5.8 절의 판단과 같다).
      if [ -n "$PYENC_NATIVE" ] && [ "$(_lc "$PYENC_NATIVE")" != "utf8" ]; then
        printf '  \xe2\x84\xb9 이 PC 의 맨 로케일은 %s 입니다 — 플러그인이 UTF-8 로 고정해 막고 있습니다\n' "$PYENC_NATIVE"
        fix "플러그인을 거치지 않고 스크립트를 직접 돌리면 한글이 깨집니다: export PYTHONUTF8=1 PYTHONIOENCODING=utf-8"
      fi
      ;;
    "")
      ng "Python stdout 인코딩 확인 실패"
      fix "$PS_PY -c 'import sys;print(sys.stdout.encoding)' 를 직접 실행해 오류를 확인하세요" ;;
    *)
      ng "Python stdout 인코딩이 $PYENC_EFF — 한글이 깨진 채 Slack·Notion 에 발신됩니다"
      fix "플러그인을 최신본(v1.19.2+)으로 갱신: /plugin → ax@ax-harness 업데이트"
      fix "그래도 남으면 셸에서: export PYTHONUTF8=1 PYTHONIOENCODING=utf-8" ;;
  esac
fi

# 1) GitHub gh — 설치/인증을 구분해 안내
#   판정은 `gh auth status` 종료코드가 아니라 **실제 API 호출**로 한다.
#   gh 는 등록된 계정이 여럿일 때 그중 **하나라도** 토큰이 만료면 exit 1 을 낸다 —
#   활성 계정이 멀쩡해도 "로그인 필요" 로 오탐했다(2026-08-07 실측: 활성 gh-user 정상,
#   비활성 hank-netpg 키체인 토큰 만료 → doctor 가 ✗ 보고). 사용자는 멀쩡한 로그인을 다시 하게 된다.
if ! command -v gh >/dev/null 2>&1; then
  ng "GitHub CLI(gh) 미설치"; fix "설치: https://cli.github.com  (mac: brew install gh)"
elif [ -z "${GH_LOGIN:=$(gh api user --jq .login 2>/dev/null)}" ]; then
  ng "GitHub: 로그인 필요(또는 활성 계정 토큰 만료)"
  fix "터미널에서: gh auth login    (계정이 여럿이면: gh auth switch 로 활성 계정 확인)"
else
  ok "GitHub: 로그인됨 ($GH_LOGIN)"
  # org 멤버십 — registry·secrets(토큰)·repo 접근의 전제. 아니면 이후 단계가 다 막힘.
  ORG="${PS_ORG:-ax-harness}"
  MSTATE="$(gh api "user/memberships/orgs/$ORG" --jq '.state' 2>/dev/null)"
  if [ "$MSTATE" = "active" ]; then
    ok "GitHub org: $ORG 멤버 (registry·토큰·repo 접근 가능)"
  elif [ "$MSTATE" = "pending" ]; then
    ng "GitHub org: $ORG 초대 수락 대기중"; fix "GitHub 알림/메일에서 $ORG 초대를 수락한 뒤 다시 점검하세요."
  else
    ng "GitHub org: $ORG 멤버 아님 — registry·Slack토큰·clone 이 모두 막힙니다"
    fix "Slack에서 엔지니어링팀 관리자(@관리자, admin@example.com)에게 $ORG org 멤버 등록을 요청하세요."
    fix "(이미 다른 계정이 $ORG 멤버라면: gh auth switch 로 전환)"
  fi
  # repo write 권한 (github-push 전제) — org 멤버여도 repo 가 read-only 면 push 거부됨
  GHR="$(ps_cfg '.github.org' 2>/dev/null)/$(ps_cfg '.github.repo' 2>/dev/null)"
  if [ "$GHR" != "/" ]; then
    PUSH="$(gh api "repos/$GHR" --jq '.permissions.push' 2>/dev/null)"
    if [ "$PUSH" = "true" ]; then ok "GitHub repo: $GHR write 권한 ✓"
    elif [ "$PUSH" = "false" ]; then ng "GitHub repo: $GHR read-only — github-push 불가"; fix "엔지니어링팀 관리자(@관리자)에게 이 repo write 권한을 요청하세요."
    else ng "GitHub repo: $GHR 접근 불가/미존재"; fix "repo 이름 확인 또는 관리자에게 접근 요청."; fi
  fi
fi

# 2) Git LFS
if command -v git-lfs >/dev/null 2>&1; then ok "Git LFS: $(git lfs version 2>/dev/null | head -1)"
else ng "Git LFS 미설치 (대용량 첨부 push에 필요)"; fix "$LFS_FIX"; fi

# 3) Slack — 토큰 단계별 친절 진단 → 통과 시 auth.test 1회로 인증+scope 동시 점검
ENV_PATH="$PS_ROOT/.env"
PS_SLACK_TOKEN="$(ps_slack_token)"
# .env 의 원문 값 — 해석이 예시값을 걸러낸 뒤에도 **왜** 없는지를 말해주기 위해 따로 읽는다.
ENV_SLACK_RAW=""
[ -f "$ENV_PATH" ] && ENV_SLACK_RAW="$(grep -E '^[[:space:]]*PROJ_SYNC_SLACK_BOT_TOKEN=' "$ENV_PATH" 2>/dev/null \
  | tail -1 | sed 's/^[^=]*=//' | tr -d '"'"'" )"
if [ -z "$PS_SLACK_TOKEN" ] || [ "$PS_SLACK_TOKEN" = "__GH_AUTH__" ]; then
  if [ -n "$ENV_SLACK_RAW" ] && ps_is_placeholder "$ENV_SLACK_RAW"; then
    # 예시값은 이제 폴백을 막지 않는다(issue #20). 여기까지 왔다는 건 폴백까지 전부 실패했다는 뜻.
    ng "Slack: 봇 토큰 미설정 — .env 는 예시값이고, 전역 캐시·팀 저장소 조회도 실패했습니다"
    fix "팀 공용 토큰 자동 조회:  gh auth login  →  /ax:auth  (토큰 입력 불필요, ax-harness 멤버)"
    fix "개인 토큰을 쓰려면 $ENV_PATH 의 PROJ_SYNC_SLACK_BOT_TOKEN 에 실제 xoxb- 토큰을 넣으세요."
  else
    ng "Slack: 봇 토큰 미설정 (자동 조회도 실패)"
    fix "GitHub 로그인 후 자동 설정:  gh auth login  →  /ax:auth  (토큰 입력 불필요, ax-harness 멤버 자동 조회)"
    fix "또는 직접: $ENV_PATH 의 PROJ_SYNC_SLACK_BOT_TOKEN= 뒤에 xoxb- 토큰 입력."
  fi
elif [ "${PS_SLACK_TOKEN#xoxb-}" = "$PS_SLACK_TOKEN" ]; then
  ng "Slack: 토큰 형식 오류 (xoxb- 로 시작해야 함)"
  fix "$ENV_PATH 의 PROJ_SYNC_SLACK_BOT_TOKEN 에 실제 봇 토큰(xoxb-...)을 넣으세요."
else
  HDR="$(mktemp)"; BODY="$(mktemp)"
  if ps_slack_auth_into "$HDR" "$BODY"; then
    PARSED="$("$PS_PY" - "$BODY" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: d={}
print("%s\t%s\t%s" % (1 if d.get("ok") else 0, d.get("team",""), d.get("error","")))
PY
)"
    IFS=$'\t' read -r SOK STEAM SERR <<< "$PARSED"
    if [ "$SOK" = "1" ]; then
      ok "Slack: 인증됨 (team=$STEAM)"
      SCOPES="$(grep -i '^x-oauth-scopes' "$HDR" | sed 's/^[^:]*: *//' | tr -d '\r')"
      MISS=""
      for s in channels:history files:read files:write; do
        echo "$SCOPES" | tr ',' '\n' | grep -qx "$s" || MISS="$MISS $s"
      done
      if [ -z "$MISS" ]; then ok "Slack 권한(scope): channels:history, files:read, files:write"
      else
        ng "Slack 권한 부족 →$MISS"
        fix "api.slack.com/apps → 해당 앱 → OAuth & Permissions 에서 scope 추가 후 'Reinstall to Workspace'."
      fi
      # inbox 회신(chat.postMessage)용 scope — 읽기·업로드에는 불필요, slack_post.sh 에만 필요
      if echo "$SCOPES" | tr ',' '\n' | grep -qx "chat:write"; then
        ok "Slack scope: chat:write (inbox 회신 가능)"
      else
        ng "Slack scope: chat:write 없음 — inbox 회신(slack_post.sh)만 불가 (수신·업로드는 정상)"
        fix "api.slack.com/apps → OAuth & Permissions 에 chat:write 추가 후 'Reinstall to Workspace'."
      fi
      printf '  \xe2\x84\xb9 비공개 채널 프로젝트는 inbox 폴링에 groups:history scope 도 필요 (공개 채널은 channels:history 로 충분).\n'
      # 봇이 이 프로젝트 채널의 멤버인지 (slack-pull/push 전제) — conversations.info 의 is_member
      CH="$(ps_cfg '.slack.channel_id' 2>/dev/null)"
      if [ -n "$CH" ]; then
        CF="$(mktemp)"; ps_curl -s "https://slack.com/api/conversations.info?channel=$CH" -o "$CF"
        CRES="$("$PS_PY" - "$CF" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); ch=d.get("channel") or {}
if d.get("ok") and ch.get("is_member"): print("member %s" % ch.get("name",""))
elif d.get("ok"): print("notmember %s" % ch.get("name",""))
elif d.get("error")=="channel_not_found": print("notfound -")
else: print("err %s" % d.get("error",""))
PY
)"; rm -f "$CF"
        case "${CRES%% *}" in
          member) ok "Slack 채널: AX-E 봇이 멤버 (#${CRES#* })" ;;
          notmember|notfound)
            ng "Slack 채널: AX-E 봇이 이 채널에 없음 → slack-pull/push 동작 안 함"
            fix "해당 Slack 채널에서  /invite @AX-E  로 봇을 초대하세요. (비공개 채널은 채널 멤버가 직접 초대)" ;;
          *) ng "Slack 채널 멤버십 확인 실패 (${CRES#* })" ;;
        esac
      else
        ng "Slack 채널: config에 채널 미지정 — slack-pull/push 불가"
        fix "/ax:init 실행 → Claude가 채널 ID(C…)를 물어 Notion 수행 프로젝트 DB·config 에 반영합니다."
      fi
    else
      ng "Slack: 인증 실패 (${SERR:-알 수 없는 오류})"
      [ "$SERR" = "invalid_auth" ] && fix "토큰이 만료/오타일 수 있음 → Slack 앱에서 봇 토큰 재확인 후 .env 갱신."
    fi
  else
    ng "Slack: 네트워크 오류 (Slack 접속 실패)"; fix "인터넷 연결/프록시 설정을 확인하세요."
  fi
  rm -f "$HDR" "$BODY"
fi

# 3.2) Notion — 설정 완결성 점검
#   게시는 **로그인한 사용자의 claude.ai Notion 커넥터**가 한다(v1.21.0 — 팀 REST 경로 삭제).
#   토큰이 없으므로 스크립트는 토큰을 보지 않는다 — 커넥터 연결 여부는 Claude 세션이
#   notion-fetch 로 확인한다(commands/doctor.md). provider=notion_api 잔존 config 는 ng 로 알린다.
NOTION_DS="$(ps_cfg '.notion.data_source_id' 2>/dev/null || true)"; [ "$NOTION_DS" = "null" ] && NOTION_DS=""
NOTION_PROV="$(ps_cfg '.notion.provider' 2>/dev/null || true)"
[ -z "$NOTION_PROV" ] || [ "$NOTION_PROV" = "null" ] && NOTION_PROV="claude_ai_mcp"
if [ "$(ps_cfg '.notion.enabled' 2>/dev/null)" = "true" ] || [ -n "$NOTION_DS" ]; then
  if [ -z "$NOTION_DS" ]; then
    ng "Notion: data_source_id 미설정 — 문서함 게시 불가"
    fix "config.notion.data_source_id 에 문서함 data source ID 를 넣으세요."
  elif [ "$NOTION_PROV" = "notion_api" ]; then
    ng "Notion: config 에 provider=notion_api 가 남아 있습니다 — v1.21.0 에서 팀 REST 경로가 삭제됐습니다"
    fix ".proj-sync/config.json 에서 notion.provider 를 지우거나 \"claude_ai_mcp\" 로 바꾸세요. 게시는 본인의 claude.ai Notion 커넥터가 합니다."
  else
    ok "Notion: provider=$NOTION_PROV → claude.ai Notion 커넥터(MCP) 경로 — 토큰 불요"
    printf '  \xe2\x84\xb9 커넥터 연결은 이 doctor(bash)가 볼 수 없습니다 — Claude 세션이 notion-fetch 로 확인합니다(각자 1회 연동 · /mcp 로 상태 확인).\n'
  fi
  # 프로젝트 태그 — 없으면 사업별 뷰에서 빠지고 고아 스윕(태그 기준)도 돌지 않는다.
  NOTION_TAG="$(ps_cfg '.notion.project_tag' 2>/dev/null || true)"
  if [ -z "$NOTION_TAG" ] || [ "$NOTION_TAG" = "null" ]; then
    ng "Notion: project_tag 미설정 — 사업별 뷰 누락·고아 스윕 불가"
    fix "config.notion.project_tag 에 수행 프로젝트 DB 의 notion_tag 값을 넣으세요."
  fi
  # 게시 대상 집합 — 이게 없으면 토큰·접근이 다 정상이어도 아무것도 올라가지 않는다.
  # 2026-08-02 실측: 15개 사업 중 easypatent 외에는 대상 규칙이 없어 GitHub 산출물
  # 439건 중 Notion 반영이 사실상 부재했다. 조용한 실패라 지금까지 보이지 않았다.
  if [ "$(ps_cfg '.notion.publish.globs' 2>/dev/null)" = "" ] \
     || [ "$(ps_cfg '.notion.publish.globs' 2>/dev/null)" = "null" ]; then
    ng "Notion: 게시 대상 미정의 (config.notion.publish.globs) — 동기화해도 게시되지 않음"
    fix "config 에 추가:  \"publish\": { \"globs\": [\"reference/drafts/**/*.md\"] }  → /ax:sync"
  fi
else
  # 종전에는 enabled=false 이고 data_source_id 도 없으면 이 절 전체를 건너뛰어,
  # Notion 축이 꺼져 있다는 사실 자체가 doctor 출력에 나타나지 않았다.
  ng "Notion: 축 미가동 (enabled=false·data_source_id 미설정) — 게시본이 갱신되지 않습니다"
  fix "쓰려면 config.notion 에 enabled=true · data_source_id · project_tag · publish.globs 를 설정하세요(토큰 불요 — 각자의 claude.ai 커넥터). 안 쓸 사업이면 그대로 두어도 됩니다."
fi

# 3.5) 수행 프로젝트 레지스트리 (init 기존-선택용 미러)
REG_ORG="${PS_REGISTRY_ORG:-ax-harness}"; REG_REPO="${PS_REGISTRY_REPO:-proj-sync-registry}"
if command -v gh >/dev/null 2>&1 && [ -n "${GH_LOGIN:=$(gh api user --jq .login 2>/dev/null)}" ]; then
  if gh api "repos/$REG_ORG/$REG_REPO/contents/registry.json" --jq '.name' >/dev/null 2>&1; then
    ok "레지스트리: $REG_ORG/$REG_REPO 접근 가능 (init 시 기존 프로젝트 선택 가능)"
  else
    printf '  \xe2\x84\xb9 레지스트리: %s/%s 미접근 — init은 수동 입력으로 진행됩니다.\n' "$REG_ORG" "$REG_REPO"
  fi
fi

# 4) (v1.21.0 에서 3.2 절에 흡수 — Notion 커넥터 안내는 provider 판정 줄에 함께 나온다)

# 5) Google Drive (사무파일 대용량 저장소) — enabled 일 때만 점검
#   v1.19.0 에서 NAS(Synology)를 대체했다. 전송은 rclone 이 한다 — claude.ai Drive 커넥터에는
#   로컬 경로 업로드가 없어 파일을 base64 로 컨텍스트에 두 번 통과시켜야 하고(64KiB≈70k 토큰),
#   대용량이 이 저장소의 존재 이유이기 때문이다. 커넥터는 조회·공유 보조로만 쓴다.
#   자격증명은 사용자 본인 Google 계정(팀 토큰 아님) — `gdrive_sync.sh setup-remote` 가
#   rclone 기본 client 로 remote 를 만든다(머신당 1회 · 브라우저 인증 · v1.21.0 개인 OAuth 단일화).
if [ "$(ps_cfg '.gdrive.enabled')" = "true" ]; then
  GD_REMOTE="$(ps_cfg '.gdrive.remote')"; [ -z "$GD_REMOTE" ] || [ "$GD_REMOTE" = "null" ] && GD_REMOTE="gdrive"
  if ! command -v rclone >/dev/null 2>&1; then
    ng "Google Drive: rclone 미설치 (대용량 전송 불가)"
    case "$OS" in
      mac) fix "설치:  brew install rclone" ;;
      win) fix "설치:  https://rclone.org/downloads/ (Windows 64-bit)" ;;
      *)   fix "설치:  sudo apt install rclone  (또는 https://rclone.org/install.sh)" ;;
    esac
  elif ! rclone listremotes 2>/dev/null | grep -qx "$GD_REMOTE:"; then
    ng "Google Drive: rclone remote '$GD_REMOTE' 미설정"
    fix "머신당 1회:  bash \"$HERE/gdrive_sync.sh\" setup-remote   (본인 Google 계정 · 브라우저 인증 1회)"
  else
    # 자가진단에 위임한다 — 판정 지식을 두 벌로 두지 않는다(gdrive_sync.sh 가 SSOT).
    bash "$HERE/gdrive_sync.sh" doctor --quick >/dev/null 2>&1
    GRC=$?
    case "$GRC" in
      0)  ok "Google Drive: remote '$GD_REMOTE' 인증됨 (본인 Google 계정 · 사무파일 동기화 준비됨)" ;;
      11) ng "Google Drive: remote '$GD_REMOTE' 도달·인증 불가 (네트워크 또는 토큰 만료)"
          fix "재인증:  rclone config reconnect $GD_REMOTE:" ;;
      12) ng "Google Drive: remote '$GD_REMOTE' 가 조직 정책으로 차단됨 (Workspace 관리자의 서드파티 앱 차단)"
          fix "Workspace 관리자에게 rclone 허용(관리 콘솔 → 앱 접근 통제)을 요청하세요 — 재인증·재생성으로는 풀리지 않습니다." ;;
      13) ng "Google Drive: base_path 미설정 (config.gdrive.team_folder 확인)"
          fix "재init(기존 설정 보존):  PS_FORCE=1 PS_GDRIVE_TEAM=<팀폴더> bash \"$(ps_plugin_root)/scripts/init.sh\"" ;;
      14) ng "Google Drive: 쓰기 권한 실패"
          fix "대상 폴더의 공유 권한(편집자)을 확인하세요. 상세: bash \"$HERE/gdrive_sync.sh\" doctor" ;;
      *)  ng "Google Drive: 자가진단 실패 (E$GRC)"
          fix "상세 진단: bash \"$HERE/gdrive_sync.sh\" doctor" ;;
    esac
    printf '  \xe2\x84\xb9 Drive 자격증명은 rclone 이 보관합니다(.env 불요 · 사용자 본인 계정). 수동 열람은 브라우저 Drive.\n'
  fi
fi

# 5.1) 남은 nas 키 안내 — v1.19.0 이 Google Drive 로 교체했지만, 마이그레이션은 additive 라
#   기존 config 의 nas 블록을 지우지 않는다(불변식). 읽는 코드가 없어 무해하지만,
#   남아 있으면 다음 사람이 「아직 NAS 를 쓰나?」로 읽는다. 사람이 확인하고 지우도록 알린다.
if [ "$(ps_cfg '.nas.enabled' 2>/dev/null)" != "" ] && [ "$(ps_cfg '.nas.enabled' 2>/dev/null)" != "null" ]; then
  printf '  \xe2\x84\xb9 config 에 사용하지 않는 nas 블록이 남아 있습니다 (v1.19.0 에서 Google Drive 로 교체)\n'
  fix "확인 후 .proj-sync/config.json 에서 \"nas\" 키를 지우세요. 자동 삭제하지 않습니다(additive 불변식)."
fi

# 5.2) 남은 gdrive.auth 키 안내 — v1.21.0 이 개인 rclone OAuth 로 단일화해 읽는 코드가 없다.
#   nas 블록과 같은 이유로 자동 삭제하지 않고 사람이 확인·삭제하도록 알린다.
if [ "$(ps_cfg '.gdrive.auth' 2>/dev/null)" != "" ] && [ "$(ps_cfg '.gdrive.auth' 2>/dev/null)" != "null" ]; then
  printf '  \xe2\x84\xb9 config 에 사용하지 않는 gdrive.auth 키가 남아 있습니다 (v1.21.0 — 개인 rclone OAuth 로 단일화)\n'
  fix "확인 후 .proj-sync/config.json 에서 \"gdrive\".\"auth\" 키를 지우세요. 자동 삭제하지 않습니다(additive 불변식)."
fi

# 5.5) 제안축·오케스트레이션 파이프라인 런타임 의존성 (선택 — 사용 시 필요)
echo "· 제안축 파이프라인 런타임 (제안서 자동화 사용 시)"
# Node.js v18+ (docquark 지식맵)
if command -v node >/dev/null 2>&1; then
  NV="$(node -v 2>/dev/null | sed 's/^v//')"; NMAJ="${NV%%.*}"
  if [ "${NMAJ:-0}" -ge 18 ] 2>/dev/null; then ok "Node.js: v$NV (docquark 지식맵)"
  else printf '  \xe2\x84\xb9 Node.js v%s < v18 (docquark 권장 v18+)\n' "$NV"; fi
else
  printf '  \xe2\x84\xb9 Node.js 미설치 — docquark(지식맵) 미동작\n'
  case "$OS" in mac) fix "brew install node";; *) fix "sudo apt install nodejs (또는 nodejs.org, v18+)";; esac
fi
# Python 패키지 (build-deck·hitl·회의록)
if [ -n "$PS_PY" ]; then
  for mod in "pptx:python-pptx:build-deck(PPTX)" "yaml:PyYAML:hitl_scan·회의록·전제" "lxml:lxml:회의록 HWPX"; do
    M="${mod%%:*}"; rest="${mod#*:}"; PKG="${rest%%:*}"; USE="${rest#*:}"
    if "$PS_PY" -c "import $M" >/dev/null 2>&1; then ok "Python·$PKG ($USE)"
    else printf '  \xe2\x84\xb9 Python·%s 미설치 — %s 미동작\n' "$PKG" "$USE"; fix "$PS_PY -m pip install --user $PKG"; fi
  done
  # jsonschema (선택 — 스키마 검증)
  "$PS_PY" -c "import jsonschema" >/dev/null 2>&1 && ok "Python·jsonschema (스키마 검증, 선택)" \
    || printf '  \xe2\x84\xb9 Python·jsonschema 미설치(선택) — 스키마 자동검증만 생략\n'
fi

# 5.8) CLAUDE.md 프로젝트별 슬롯 (issue #25)
# 9원칙 §0 은 「1순위 정의」가 비면 2순위가 최상위가 되고, §7 은 「비어 있으면 이 문서는
# 절반만 작동한다」고 못박는다. 스캐폴드는 슬롯을 「미정」으로 만들 뿐이라, 신규는 /ax:init 가
# 묻지만 **기존 사업은 비대화형 마이그레이션 경로라 물을 수 없다** — 여기서 안내한다.
#
# ⚠ 의도적으로 ℹ 다. ✗ 로 세면 슬롯 하나 때문에 /ax:sync 1단계가 막힌다(sync.md:10).
#   0.2 절 주석의 판단과 같다 — 「지금 막힌 문제」가 아닌 것을 ✗ 로 만들면 ✗ 의 뜻이 흐려진다.
if [ -f "$PS_ROOT/CLAUDE.md" ]; then
  CM_EMPTY="$(grep -c '_(미정 — 채울 것)_' "$PS_ROOT/CLAUDE.md" 2>/dev/null || true)"
  if [ "${CM_EMPTY:-0}" -gt 0 ]; then
    printf '  \xe2\x84\xb9 CLAUDE.md 슬롯 %s개가 미정입니다 — 9원칙이 절반만 작동합니다\n' "$CM_EMPTY"
    fix "CLAUDE.md 의 「1순위 정의」·「회귀 게이트」를 채우세요 (근거: reference/9원칙.md §0·§7)"
  else
    ok "CLAUDE.md: 프로젝트별 슬롯 채워짐"
  fi
fi

# 5.9) 산출물 문서버전·개정이력
# 발주처 제출물은 **문서 자체에** 표지 Version·개정일자·개정이력이 있어야 하고 감리가 그것을 본다.
# git 커밋 이력은 내부 형상관리라 이를 대신하지 못한다.
# 2026-08-03 실측: reference/drafts md 138건 중 114건(82%)이 버전 표기 전무였다.
if [ -n "$PS_PY" ] && [ -f "$HERE/doc_version.py" ] && [ -d "$PS_ROOT/reference/drafts" ]; then
  DV="$("$PS_PY" "$HERE/doc_version.py" check --standard-only --root "$PS_ROOT" 2>/dev/null)"
  DVN="$(printf '%s' "$DV" | sed -n 's/.*누락 \([0-9]*\)건.*/\1/p')"
  if [ "${DVN:-0}" -gt 0 ]; then
    ng "산출물 버전 표기 누락 ${DVN}건 — 문서 내 버전·개정이력이 없으면 제출 결함"
    fix "확인:  $PS_PY \${CLAUDE_PLUGIN_ROOT}/scripts/doc_version.py check --standard-only
       보정:  … doc_version.py fix --dry-run  →  … fix   (사무파일은 표지 Version·개정이력 시트를 직접)"
  else
    ok "산출물 버전 표기 (표준 산출물 전건)"
  fi
fi

# 6) 대용량·MCP 접근 안내 (자주 겪는 마찰 예방)
printf '  \xe2\x84\xb9 대용량(>10MB): Slack MCP 는 10MB 초과 파일을 못 받음 → slack_download.sh(봇 토큰) 또는 브라우저. Drive 업로드는 gdrive_sync.sh push / push-file.\n'
printf '  \xe2\x84\xb9 Slack MCP 이원성: slack-bot(봇 토큰) 과 claude_ai_Slack(사용자 커넥터) 는 접근 가능 채널이 다를 수 있음 — 한쪽에서 channel_not_found 면 다른 쪽 시도.\n'
printf '  \xe2\x84\xb9 개인 커넥터(Slack·Notion)는 Claude 세션에서 확인합니다 — /mcp 로 연결 상태, 미연동이면 claude.ai 커넥터 설정(각자 1회).\n'

echo "------------------------------------"
echo "결과: ✓ $OK / ✗ $FAIL"
if [ "$FAIL" -eq 0 ]; then
  echo "→ 모두 정상입니다. 이제 /ax:sync 로 동기화하세요."
  exit 0
else
  echo "→ 위 ✗ 의 ↳ 안내대로 조치한 뒤 /ax:doctor 를 다시 실행하세요."
  exit 1
fi
