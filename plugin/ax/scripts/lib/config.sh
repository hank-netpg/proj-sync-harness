#!/usr/bin/env bash
# proj-sync 공통 라이브러리 — config.json 로드·검증, token_ref 해석
# 사용: source 이 파일 후 ps_load_config / ps_cfg / ps_resolve_token
set -euo pipefail

# Homebrew 경로 보강 (mac: node/jq 등). Windows Git Bash 에서는 무해.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Python stdio 를 **로케일에서 분리**한다.
#   `print()` 는 sys.stdout.encoding 으로 인코딩하는데, stdout 이 파이프($(...))면 그 값은
#   로케일 기본 인코딩이다 — 한국어 Windows 에서는 cp949. 그래서 Slack·Notion 페이로드가
#   CP949 바이트로 만들어진 채 `charset=utf-8` 로 전송돼 한글이 통째로 깨졌다.
#   (2026-08-26 실측: "동기화 완료" → "????ȭ ?Ϸ?". 화=C8AD 가 UTF-8 2바이트로 오독돼 U+022D.)
#   mac/linux 는 로케일 기본이 UTF-8 이라 같은 코드가 정상 동작해 여태 드러나지 않았다.
#   PYTHONUTF8 만으로는 부족하다 — PYTHONIOENCODING 이 이미 있으면 그쪽이 이긴다. 둘 다 건다.
export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8

# Python 실행기 결정 — mac/linux: python3, Windows(Git Bash): python 인 경우가 많음
ps_python() {
  if command -v python3 >/dev/null 2>&1; then echo python3
  elif command -v python >/dev/null 2>&1; then echo python
  else echo ""; fi
}
PS_PY="${PS_PY:-$(ps_python)}"
export PS_PY
if [ -z "$PS_PY" ]; then
  echo "[proj-sync] Python 미발견. python3(또는 python) 설치 필요. (mac: brew install python / win: python.org)" >&2
fi

PS_CONFIG_PATH="${PS_CONFIG_PATH:-.proj-sync/config.json}"

# 프로젝트 루트 탐색 (.proj-sync/config.json 가 있는 가장 가까운 상위 디렉토리)
ps_find_root() {
  local d="$PWD"
  while [ "$d" != "/" ]; do
    [ -f "$d/.proj-sync/config.json" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  return 1
}

# config 존재 확인 + 경로 export
ps_load_config() {
  local root
  if ! root="$(ps_find_root)"; then
    echo "[proj-sync] config 없음: .proj-sync/config.json 를 찾지 못했습니다. /ax:init 를 먼저 실행하세요." >&2
    return 1
  fi
  export PS_ROOT="$root"
  export PS_CONFIG="$root/.proj-sync/config.json"
  # .env 로드 (있으면)
  if [ -f "$root/.env" ]; then
    set -a; . "$root/.env"; set +a
  fi
  return 0
}

# config 다중 조회: ps_cfg_get '.a.b' '.c.d' …  → 인자 순서대로 한 줄씩 출력
# python 인터프리터를 1회만 띄워 여러 값을 모음 (호출당 ~28ms startup 절약)
# 경로/쿼리를 소스 보간이 아닌 argv로 전달 (특수문자 안전)
#
# ⚠ 여기서 나온 값은 채널ID·경로·사업명이 되어 **모든 후속 단계로 흘러간다.** 그래서
#   출력 바이트를 print() 에 맡기지 않고 직접 쓴다:
#     - 인코딩: print() 는 로케일로 인코딩한다(위 PYTHONIOENCODING 참고). 사업명에 한글이 있다.
#     - 개행:   Windows 에서 CRLF 가 섞여 들어온 사례가 보고됐다(2026-08-26, ceddcfb 동기화
#               보고에 "Windows CRLF 결함(ps_cfg_get) 로컬 패치" 로 기록됨. 그 패치는 업스트림에
#               올라오지 않았다). $(...) 는 후행 \n 만 걷어내므로 \r 이 남으면 값 끝에 달라붙어
#               비교·URL·경로가 조용히 어긋난다. 기전이 무엇이든 바이트를 직접 쓰면 영향받지 않는다.
ps_cfg_get() {
  "$PS_PY" - "$PS_CONFIG" "$@" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
def get(path):
    cur=d
    for p in path.lstrip('.').split('.'):
        if not p: continue
        cur=cur.get(p) if isinstance(cur,dict) else None
        if cur is None: break
    return '' if cur is None else (cur if isinstance(cur,str) else json.dumps(cur,ensure_ascii=False))
out="".join(get(a)+"\n" for a in sys.argv[2:])
sys.stdout.buffer.write(out.encode('utf-8'))
PY
}

# 단일 조회: ps_cfg '.slack.channel_id'  (배치 헬퍼 재사용)
ps_cfg() { ps_cfg_get "$1"; }

# token_ref 해석:
#   "env:VAR"               → $VAR
#   "gh:"                   → (gh auth 사용 표시)
#   "keychain:SERVICE"      → security -s SERVICE
#   "keychain:SERVICE:ACCT" → security -a ACCT -s SERVICE
#   그 외 평문               → 그대로
ps_resolve_token() {
  local ref="$1"
  case "$ref" in
    env:*)  local var="${ref#env:}"; echo "${!var:-}" ;;
    gh:*)   echo "__GH_AUTH__" ;;
    keychain:*)
      # keychain 은 macOS 전용(security). 타 OS 에서는 빈값 반환.
      if ! command -v security >/dev/null 2>&1; then echo ""; return 0; fi
      local spec="${ref#keychain:}" svc acct
      svc="${spec%%:*}"; acct="${spec#*:}"
      if [ "$acct" = "$spec" ]; then
        security find-generic-password -s "$svc" -w 2>/dev/null || echo ""
      else
        security find-generic-password -a "$acct" -s "$svc" -w 2>/dev/null || echo ""
      fi
      ;;
    *)      echo "$ref" ;;
  esac
}

# 전역 자격증명(크로스플랫폼: mac·linux·Windows Git Bash 모두 ~ 존재). OS 키체인 대신 홈파일 사용.
PS_GLOBAL_CRED="${PS_GLOBAL_CRED:-$HOME/.proj-sync/credentials}"
PS_SECRETS_REPO="${PS_SECRETS_REPO:-<your-org>/proj-sync-secrets}"
PS_SECRETS_FILE="${PS_SECRETS_FILE:-credentials}"

# 전역 캐시에서 키 1개 읽기 (env 형식 KEY=…). 인자 없으면 Slack 봇 토큰(하위호환).
ps_global_token() {
  local key="${1:-PROJ_SYNC_SLACK_BOT_TOKEN}"
  [ -f "$PS_GLOBAL_CRED" ] || { echo ""; return 0; }
  # 키가 없으면 grep 이 1 → pipefail 로 파이프 전체가 1 → `set -e` 인 호출부(auth.sh)가 대입문에서 죽는다.
  #   「없음」은 오류가 아니라 빈 값이다 — 항상 0 을 돌려준다.
  grep -E "^${key}=" "$PS_GLOBAL_CRED" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"\r' || true
}

# 전역 캐시에 키 1개를 기록 — **같은 KEY 줄만 바꾸고 나머지 줄은 보존**한다.
#   종전 auth.sh set 은 파일 전체를 Slack 한 줄로 덮어써 함께 캐시된 다른 키(Notion·Drive)를 지웠다.
#   임시파일에 쓴 뒤 mv 하므로 중간에 끊겨도 반쪽 파일이 남지 않는다.
ps_cred_set() {   # ps_cred_set KEY VALUE
  local key="$1" val="$2" tmp
  mkdir -p "$(dirname "$PS_GLOBAL_CRED")"
  tmp="$(mktemp "$(dirname "$PS_GLOBAL_CRED")/.cred.XXXXXX")" || return 1
  # grep -v 는 남는 줄이 없으면 1 을 돌려준다 — set -e 인 호출부(auth.sh)가 죽지 않게 || true.
  { { [ -f "$PS_GLOBAL_CRED" ] && grep -vE "^${key}=" "$PS_GLOBAL_CRED"; } || true; printf '%s=%s\n' "$key" "$val"; } > "$tmp"
  chmod 600 "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$PS_GLOBAL_CRED"
}

# gh 기본 인증이 막힐 때 시도할 대체 GitHub 토큰(키체인 보관분).
#   조직이 classic PAT(ghp_)를 차단하면 gh 기본 계정으로는 403 이 난다. 이때 fine-grained PAT
#   (github_pat_)를 키체인에 넣어두면 아래 순서로 자동 승계된다. macOS 외 OS 는 조용히 건너뜀.
PS_GH_TOKEN_KEYCHAIN="${PS_GH_TOKEN_KEYCHAIN:-github-fine-grained-token github-token-ax-harness}"

ps_gh_token_candidates() {   # stdout: 시도할 토큰 목록(1줄 1개). 없으면 아무것도 출력 안 함.
  [ "$(uname -s)" = "Darwin" ] || return 0
  command -v security >/dev/null 2>&1 || return 0
  local svc tok
  for svc in $PS_GH_TOKEN_KEYCHAIN; do
    tok="$(security find-generic-password -s "$svc" -w 2>/dev/null || true)"
    [ -n "$tok" ] && printf '%s\n' "$tok"
  done
  return 0
}

# private repo의 파일 1개를 gh로 내려받아 stdout.
#   1순위: gh 기본 인증(org 멤버십이 접근통제) → 2순위: 키체인 fine-grained PAT 승계.
# registry.json·secrets 등 공용 fetch 진입점.
ps_gh_file() {  # ps_gh_file <owner/repo> <path>
  command -v gh >/dev/null 2>&1 || return 1
  local out tok
  out="$(gh api "repos/$1/contents/$2" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || true)"
  [ -n "$out" ] && { printf '%s' "$out"; return 0; }
  while IFS= read -r tok; do
    [ -z "$tok" ] && continue
    out="$(GH_TOKEN="$tok" gh api "repos/$1/contents/$2" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || true)"
    [ -n "$out" ] && { printf '%s' "$out"; return 0; }
  done < <(ps_gh_token_candidates)
  return 1
}

# 전역 캐시에 지정 키들이 모두 값과 함께 존재하는지. (없으면 1)
#   팀 자격증명은 **Slack 봇 토큰(AX-E) 하나**다(v1.21.0). Notion 은 로그인 사용자의 claude.ai 커넥터,
#   Google Drive 는 rclone(본인 Google 계정)이 담당한다 — 캐시에 다른 키가 남아 있어도 읽는 코드가 없다.
ps_have_team_tokens() {   # ps_have_team_tokens [KEY…]  기본: Slack
  local keys="${*:-PROJ_SYNC_SLACK_BOT_TOKEN}" k
  [ -f "$PS_GLOBAL_CRED" ] || return 1
  for k in $keys; do
    [ -n "$(ps_global_token "$k")" ] || return 1
  done
  return 0
}

# private secrets repo 에서 토큰을 가져와 전역 캐시에 저장. 토큰은 배포 zip 에 없으며 GitHub 권한 뒤에만 존재.
#   내려받은 내용이 실제로 KEY=VALUE 형식인지 검증한 뒤에만 덮어쓴다(빈 응답·에러 페이지로 캐시 파손 방지).
ps_fetch_team_token() {
  command -v gh >/dev/null 2>&1 || return 1
  local content; content="$(ps_gh_file "$PS_SECRETS_REPO" "$PS_SECRETS_FILE")" || return 1
  [ -z "$content" ] && return 1
  printf '%s' "$content" | grep -qE '^[A-Z_]+=.+' || return 1
  mkdir -p "$(dirname "$PS_GLOBAL_CRED")"
  printf '%s' "$content" > "$PS_GLOBAL_CRED"
  chmod 600 "$PS_GLOBAL_CRED" 2>/dev/null || true
  return 0
}

# 팀 토큰(Slack)을 확보 — 이미 캐시돼 있으면 네트워크 호출 없이 통과.
#   setup.sh·init.sh·doctor.sh 가 공통으로 호출하는 진입점. 종료코드 0=확보, 1=미확보.
ps_ensure_team_tokens() {
  ps_have_team_tokens && return 0
  ps_fetch_team_token || return 1
  ps_have_team_tokens
}

# 실행 중인 플러그인 **사본**의 루트·버전 — init.sh·doctor.sh 공용.
#   CLAUDE_PLUGIN_ROOT 를 쓰지 않는다: 알아야 할 것은 "지금 이 스크립트가 속한 사본"이고,
#   그건 자기 경로에서만 나온다. (2026-08-07 실측: 같은 머신에 0.1.0·1.13.1 두 사본이 있었고
#   낡은 쪽으로 init 됐는데 산출물에 버전이 없어 사후 판별이 불가능했다 — issue #14)
ps_plugin_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd    # lib/ → scripts/ → ax/
}
ps_plugin_version() {
  local mf ver
  mf="$(ps_plugin_root)/.claude-plugin/plugin.json"
  # jq 의존 없이(설치 전에도 돌아야 함). release.yml 의 버전 추출과 같은 방식.
  ver="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[0-9][0-9.]*"' "$mf" 2>/dev/null \
         | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' | head -1)"
  echo "${ver:-unknown}"
}

# VSCode tasks 등 외부 도구가 플러그인 스크립트를 경로 고정 없이 부르도록 하는 셔임(~/.proj-sync/bin/ax).
#   플러그인 설치 경로는 사용자·버전마다 달라 tasks.json 에 하드코딩 불가 → 현재 경로를
#   ~/.proj-sync/plugin_root 에 기록하고 래퍼가 그 파일을 읽어 dispatch 한다.
#   init.sh·doctor.sh 시작부에서 호출 — doctor 가 자주 돌므로 플러그인 업데이트 후에도 자동 최신화.
ps_write_shim() {
  local plug_root bin_dir shim
  plug_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # lib/ → scripts/ → ax/
  bin_dir="$HOME/.proj-sync/bin"; shim="$bin_dir/ax"
  mkdir -p "$bin_dir" 2>/dev/null || return 0
  printf '%s\n' "$plug_root" > "$HOME/.proj-sync/plugin_root" 2>/dev/null || return 0
  cat > "$shim" <<'SHIM'
#!/usr/bin/env bash
# proj-sync 셔임 — VSCode tasks 등에서 플러그인 스크립트 호출용 (ps_write_shim 이 자동 생성·갱신)
set -uo pipefail
PR_FILE="$HOME/.proj-sync/plugin_root"
[ -f "$PR_FILE" ] || { echo "[ax] 플러그인 경로 미기록 — Claude Code 에서 /ax:doctor 를 먼저 실행하세요." >&2; exit 1; }
PLUG="$(cat "$PR_FILE")"
S="$PLUG/scripts"
[ -d "$S" ] || { echo "[ax] 플러그인 스크립트 없음: $S — Claude Code 에서 /ax:doctor 로 재기록하세요." >&2; exit 1; }
CMD="${1:-help}"; shift 2>/dev/null || true
case "$CMD" in
  doctor)      exec bash "$S/doctor.sh" "$@" ;;
  setup)       exec bash "$S/setup.sh" "$@" ;;
  slack-pull)  exec bash "$S/slack_download.sh" "$@" ;;
  slack-push)  exec bash "$S/slack_upload.sh" "$@" ;;
  slack-post)  exec bash "$S/slack_post.sh" "$@" ;;
  github-push) exec bash "$S/github_push.sh" "$@" ;;
  gdrive-push)   exec bash "$S/gdrive_sync.sh" push "$@" ;;
  gdrive-pull)   exec bash "$S/gdrive_sync.sh" pull "$@" ;;
  gdrive-doctor) exec bash "$S/gdrive_sync.sh" doctor "$@" ;;
  gdrive-status) exec bash "$S/gdrive_sync.sh" status "$@" ;;
  gdrive-setup)  exec bash "$S/gdrive_sync.sh" setup-remote "$@" ;;   # 머신당 1회 — 회사 계정용 remote 생성
  inbox)       exec bash "$S/slack_inbox.sh" poll --dry-run "$@" ;;   # 미리보기 전용(커서 미갱신) — 트리아지는 Claude 세션에서
  *) echo "사용: ax <doctor|setup|slack-pull|slack-push|slack-post|github-push|gdrive-push|gdrive-pull|gdrive-doctor|gdrive-status|gdrive-setup|inbox>"; exit 1 ;;
esac
SHIM
  chmod 755 "$shim" 2>/dev/null || true
}

# 경로 유니코드 정규화 — macOS 는 한글 파일명을 **NFD(자모 분리)** 로 저장하고,
#   Notion·GitHub 등 외부는 **NFC(완성형)** 로 돌려준다. 같은 파일인데 코드포인트 열이 다르다.
#     NFD len=53  ipnavi/reference/drafts/50_종료_인도/완료보고서.md
#     NFC len=41  ipnavi/reference/drafts/50_종료_인도/완료보고서.md
#   이 한 글자 차이가 두 가지 사고를 냈다 —
#     · 중복 게시(issue #21): 조회가 기존 페이지를 못 찾아 새 페이지를 만든다. 멱등이 깨진다
#     · 고아 오탐(issue #22): 스윕이 현행 문서를 고아로 판정해 상태를 아카이브로 민다
#   ⚠ **비교하는 양쪽이 같은 함수를 통과해야** 의미가 있다. 한쪽만 정규화하면 결과는 같다.
ps_nfc() {
  [ -n "${1:-}" ] || { echo ""; return 0; }
  # PS_PY 가 없으면 원문을 그대로 돌려준다 — 정규화 실패가 게시 자체를 막지는 않는다.
  [ -n "${PS_PY:-}" ] || { printf '%s' "$1"; return 0; }
  "$PS_PY" -c 'import sys,unicodedata; sys.stdout.write(unicodedata.normalize("NFC", sys.argv[1]))' "$1"
}

# 스캐폴드 예시값 판정 — 「값이 있다」와 「쓸 수 있는 값이다」는 다르다 (issue #20)
#   .env 템플릿이 넣어 둔 `xoxb-여기에-봇토큰-입력` 같은 값은 **비어 있지 않다.** 그래서 종전의
#   `-n` 판정은 이것을 1순위로 채택했고, 전역 캐시·팀 저장소 fetch 가 통째로 건너뛰어졌다.
#   실측(2026-08-09, 사업 17건): 예시값 13건 전부 doctor ✗ → 해당 사업의 /ax:sync 가 통째로 막힘.
#   값을 채운 게 아니라 **지우기만 했더니** 17/17 이 ✓ 가 됐다.
#
#   판정 지식이 doctor.sh 한 곳에만 있었던 것이 이 결함의 본질이다 — 진단은 예시값을 알아보는데
#   해석은 몰랐다. 그래서 판정을 여기(lib)에 두고 doctor 와 해석이 같은 함수를 쓴다.
#   ⚠ 판정은 **스캐폴드가 실제로 쓰는 형태**로 좁힌다. `xxx` 같은 흔한 조각을 부분문자열로
#     잡으면 그 조각이 우연히 든 **실토큰을 예시값으로 버린다**(랜덤 토큰에 xxx 가 낄 확률은
#     낮지만 0 이 아니고, 걸리면 「값이 있는데 안 쓰인다」는 #20 의 반대 방향 실패가 되어
#     원인을 찾기 매우 어렵다). 넓게 잡아 실토큰을 잃느니, 좁게 잡고 doctor 가 형식을 짚는 편이 낫다.
ps_is_placeholder() {   # 예시값이면 0(참)
  local v="${1:-}"
  [ -z "$v" ] && return 0
  case "$v" in
    # 템플릿·안내문에 실제로 쓰는 표현
    *여기에*|*입력*|*YOUR_*|*your-token*|*YOUR-TOKEN*) return 0 ;;
    # <...> 자리표시자 — 실토큰에는 꺾쇠가 들어가지 않는다
    *"<"*">"*) return 0 ;;
    # 접두만 있고 값이 없는 형태:  xoxb-  ·  xoxb-...  ·  ntn_...
    *-|*_) return 0 ;;
    *...*) return 0 ;;
  esac
  return 1
}

# Slack 봇 토큰 해석 — 순서: 환경변수/.env(token_ref) → 전역 캐시 → private 자동 fetch
ps_slack_token() {
  local ref tok
  ref="$(ps_cfg '.slack.token_ref' 2>/dev/null || true)"
  [ -z "$ref" ] && ref="env:PROJ_SYNC_SLACK_BOT_TOKEN"
  tok="$(ps_resolve_token "$ref")"
  if [ -n "$tok" ] && [ "$tok" != "__GH_AUTH__" ] && ! ps_is_placeholder "$tok"; then echo "$tok"; return 0; fi
  tok="$(ps_global_token)";        [ -n "$tok" ] && { echo "$tok"; return 0; }
  if ps_fetch_team_token; then tok="$(ps_global_token)"; [ -n "$tok" ] && { echo "$tok"; return 0; }; fi
  echo ""
}
