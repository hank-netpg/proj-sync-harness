#!/usr/bin/env bash
# ============================================================================
#  proj-sync 팀원 셋업 CLI  (proj-sync-setup.sh)
# ----------------------------------------------------------------------------
#  사용 순서:
#    1) 받은 proj-sync.zip 의 "압축을 먼저 풉니다".
#    2) 압축이 풀린 폴더 안(이 스크립트가 보이는 폴더)에서 아래를 실행합니다.
#
#  ⚠ 반드시 "VS Code 통합 터미널에서 직접" 실행하세요.
#     Claude Code 채팅으로 시키면 보안 분류기가 외부 스크립트 실행을 차단합니다.
#
#  실행 (Windows·macOS 공통):
#    macOS / Linux       :  bash proj-sync-setup.sh
#    Windows             :  VS Code 터미널을 "Git Bash" 로 바꾼 뒤  bash proj-sync-setup.sh
#
#  하는 일 (메뉴 선택):
#    0) (자동) 같은 폴더의 proj-sync/ 플러그인 설치 (미설치 시)
#    1) 초기 세팅  : 도구점검 → GitHub PAT → Slack 봇 토큰 → NAS 접속정보 → 작성자 선택 → 프로젝트 → doctor
#    2) Slack 다운로드/분류
#    3) Slack 파일 업로드 (메시지 앞에 [작성자] 자동 표기 → 공용 봇이어도 개인 식별)
#    4) GitHub 동기화 (push)
#    5) doctor 재점검
#  토큰: GitHub PAT = 본인 발급 / Slack·Notion = 담당자 제공값 / NAS = 본인 계정 ID·비번 직접 입력.
#  작성자: 조직 Slack 명단에서 이름 검색·번호 선택(채널 아닌 워크스페이스 전체).
#          1회 선택 → Slack 업로드 메시지·Notion 작성자 표기에 사용.
# ============================================================================
set -uo pipefail

# Windows(Git Bash) 호환: 이 파일은 반드시 LF 줄바꿈이어야 합니다.
#  · 편집기로 저장해 CRLF 로 깨졌다면 아래 한 줄로 복구 실행하세요:
#      bash <(tr -d '\r' < proj-sync-setup.sh)
IS_MAC=0; IS_WIN=0
case "$(uname -s 2>/dev/null)" in
  Darwin)               IS_MAC=1 ;;
  MINGW*|MSYS*|CYGWIN*) IS_WIN=1 ;;   # Git Bash / MSYS2 (Windows)
esac
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PS_PY_BIN="$(command -v python3 || command -v python || echo python3)"

# ── 헬퍼 ─────────────────────────────────────────────────────────────────────
ask()       { local p="$1" d="${2:-}" v; printf '%s%s: ' "$p" "${d:+ [$d]}" >&2; read -r v; printf '%s' "${v:-$d}"; }
# 토큰: 화면에 보이게 입력받고(직관성) 앞6·뒤4 마스킹으로 확인. 프롬프트는 stderr(캡처 오염 방지).
ask_token() {
  local p="$1" v
  printf '\n  ▶ %s\n    여기에 붙여넣고 Enter ▶ ' "$p" >&2
  read -r v
  if [ -n "$v" ]; then
    local n=${#v} s; [ "$n" -le 12 ] && s="****" || s="${v:0:6}…${v: -4}"
    printf '    ✓ 입력됨 (%d자): %s\n' "$n" "$s" >&2
  fi
  printf '%s' "$v"
}
hr()  { echo "────────────────────────────────────────────────────────"; }
die() { echo "✗ $*" >&2; exit 1; }

# 작성자 이름 자동 추출 — 토큰에서 가능한 만큼 추정해 "기본값"으로 제시.
#  · GitHub: gh api user 의 name(실명) → 없으면 login(아이디)
#  · Notion: internal 토큰은 owner=workspace 라 개인명이 없음(봇/워크스페이스명만) → 보조용
# 완전 자동은 불가(한글 실명은 토큰에 없을 수 있음)하므로, 사용자가 확인·수정하는 전제.
autodetect_author() {
  local n=""
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    n="$(gh api user --jq '.name // .login' 2>/dev/null)"
  fi
  printf '%s' "$n"
}
# Slack 조직(워크스페이스) 전체 활성 사용자 명단을 "이름<TAB>직책" 으로 출력.
#  · 봇 토큰의 users:read 스코프 필요. 채널이 아니라 조직 전체를 봄(users.list).
slack_org_members() {
  local tok="$1"
  [ -n "$tok" ] && command -v curl >/dev/null 2>&1 || return 1
  curl -s -H "Authorization: Bearer $tok" "https://slack.com/api/users.list?limit=1000" 2>/dev/null \
    | "$PS_PY_BIN" -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
if not d.get("ok"): sys.exit(0)
seen=set()
for m in d.get("members",[]):
    if m.get("deleted") or m.get("is_bot") or m.get("id")=="USLACKBOT": continue
    p=m.get("profile",{})
    nm=(p.get("real_name") or p.get("display_name") or "").strip()
    if not nm or nm in seen: continue
    seen.add(nm)
    print(nm + "\t" + (p.get("title","") or ""))
' 2>/dev/null
}

# 작성자 선택: 조직 명단을 이름으로 검색 → 번호 선택. 명단 불가 시 빈 출력(수동입력 폴백).
#  결과(선택된 이름)는 stdout 으로만, 안내·프롬프트는 stderr 로.
pick_author_from_org() {
  local tok="$1" members q matches n sel
  members="$(slack_org_members "$tok")" || return 0
  [ -n "$members" ] || return 0
  echo "  조직 Slack 가입자에서 본인을 찾습니다 (이름 일부 입력 → 번호 선택)." >&2
  while :; do
    q="$(ask '  이름 검색(예: 황한건 또는 황, 비우면 수동입력)')"
    [ -n "$q" ] || return 0
    # 이름(첫 컬럼)에만 매칭 — 직책 컬럼의 글자에 오매칭 방지
    matches="$(printf '%s\n' "$members" | awk -F'\t' -v q="$q" 'index($1,q)')"
    [ -n "$matches" ] || { echo "  · 일치 없음 — 다시 검색하거나 빈칸으로 수동입력." >&2; continue; }
    n=0
    while IFS=$'\t' read -r nm title; do
      n=$((n+1)); printf '    %2d) %s%s\n' "$n" "$nm" "${title:+  ($title)}" >&2
    done <<< "$matches"
    sel="$(ask '  번호 선택(다시 검색=r, 수동입력=빈칸)')"
    [ "$sel" = "r" ] && continue
    [ -n "$sel" ] || return 0
    # 숫자가 아니거나 범위를 벗어나면 재시도
    case "$sel" in *[!0-9]*) echo "  · 숫자를 입력하세요." >&2; continue ;; esac
    [ "$sel" -ge 1 ] && [ "$sel" -le "$n" ] || { echo "  · 1~$n 범위의 번호를 입력하세요." >&2; continue; }
    printf '%s\n' "$matches" | sed -n "${sel}p" | cut -f1
    return 0
  done
}

# ── 사전 점검(preflight): 실행에 필요한 도구를 한눈에 점검 + 미설치 안내 ──────
#   macOS = Homebrew 로 누락분 자동 설치 제안 / Windows·Linux = 설치 링크 안내.
#   필수(claude)는 없으면 중단, 그 외는 경고 후 진행(부분 기능 가능).
preflight() {
  hr; echo "[사전 점검] 실행에 필요한 도구를 확인합니다"; hr
  local miss_req="" miss_opt="" brew_pkgs=""
  # name|cmd|필수여부|brew패키지|안내
  local rows="
claude|claude|req||https://claude.ai/code 에서 Claude Code 설치
git|git|req|git|https://git-scm.com (Windows는 Git for Windows = Git Bash 포함)
curl|curl|req|curl|Git Bash/macOS 기본 포함
unzip|unzip|req|unzip|Git Bash/macOS 기본 포함
python3|python3|req|python|https://python.org (Windows는 PATH 등록)
gh|gh|opt|gh|https://cli.github.com (GitHub 인증용)
git-lfs|git-lfs|opt|git-lfs|https://git-lfs.github.com (대용량 파일 push용)
"
  local line name cmd req brew note
  while IFS='|' read -r name cmd req brew note; do
    [ -n "$name" ] || continue
    if command -v "$cmd" >/dev/null 2>&1; then
      printf '  ✓ %s\n' "$name"
    else
      printf '  ✗ %s — %s\n' "$name" "$note"
      [ -n "$brew" ] && brew_pkgs="$brew_pkgs $brew"
      if [ "$req" = req ]; then miss_req="$miss_req $name"; else miss_opt="$miss_opt $name"; fi
    fi
  done <<EOF
$rows
EOF

  # 누락 도구 자동 설치(macOS) 또는 안내
  if [ -n "$brew_pkgs" ]; then
    echo
    if [ "$IS_MAC" = 1 ]; then
      if command -v brew >/dev/null 2>&1; then
        if [ "$(ask '누락 도구를 Homebrew 로 지금 설치할까요? (Y/n)' Y)" != "n" ]; then
          # claude 는 brew 패키지가 아니므로 제외하고 설치
          echo "  설치 중: $brew_pkgs"
          # shellcheck disable=SC2086
          brew install $brew_pkgs 2>&1 | tail -3 || true
          command -v git-lfs >/dev/null 2>&1 && git lfs install >/dev/null 2>&1 || true
        fi
      else
        echo "  ⚠ Homebrew 가 없어 자동 설치 불가. 아래 한 줄을 터미널에 직접 붙여넣어 설치 후 재실행:"
        echo '      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
      fi
    else
      echo "  ⚠ 위 ✗ 도구를 안내 링크로 직접 설치한 뒤 다시 실행하세요. (Windows 는 Git Bash 에서)"
    fi
  fi

  # 필수 도구 재확인 (자동설치 후) — 여전히 없으면 명확히 중단
  local still=""
  for c in claude git curl unzip python3; do
    command -v "$c" >/dev/null 2>&1 || still="$still $c"
  done
  if [ -n "$still" ]; then
    echo
    die "필수 도구가 아직 없습니다:$still  → 위 안내로 설치 후 다시 실행하세요."
  fi
  [ -n "$miss_opt" ] && echo "  (참고: 선택 도구 미설치 →$miss_opt. 해당 기능 사용 시 설치 필요)"
  echo "  ✓ 사전 점검 통과"
}

# ── proj-sync scripts 경로 탐지 (+ 없으면 zip 의 install.sh 로 설치) ──────────
find_scripts() {
  local c
  # 플러그인 본체 폴더명은 `ax` 다(구 `proj-sync`). 구 이름 경로를 계속 뒤지면
  # 오래된 설치본(구 레이아웃)을 집어 현행본과 섞인다 — 현행 경로만 본다.
  # ⚠️ 버전별로 쌓이는 설치 캐시(plugins/cache/*/ax/<버전>/)는 후보에서 뺀다.
  #    glob 순서가 사전순이라 1.13.1 이 1.13.3 보다 먼저 잡힌다 — 구버전을 집는 길이다.
  for c in \
    "$HOME"/.claude/plugins/marketplaces/*/plugin/ax/scripts \
    "$HOME/.claude/marketplaces-local/ax-harness/ax/scripts" \
    "$SELF_DIR/proj-sync/ax/scripts"; do
    [ -d "$c" ] && [ -f "$c/setup.sh" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}
ensure_installed() {
  SCRIPTS="$(find_scripts)" && return 0
  echo "proj-sync 플러그인이 설치돼 있지 않습니다. 같은 폴더의 패키지로 설치합니다…"
  command -v claude >/dev/null 2>&1 || die "Claude Code CLI(claude) 가 없습니다. 먼저 Claude Code 를 설치하세요."
  # 압축을 푼 폴더 안에는 install.sh 가 있는 proj-sync/ 폴더가 함께 있어야 함.
  local inst=""
  if [ -f "$SELF_DIR/proj-sync/install.sh" ]; then
    inst="$SELF_DIR/proj-sync/install.sh"
  else
    # (예비) 같은 폴더에 proj-sync*.zip 만 있고 폴더가 없으면 풀어서 설치
    local zipf; zipf="$(ls "$SELF_DIR"/proj-sync*.zip 2>/dev/null | head -1)"
    if [ -n "$zipf" ] && command -v unzip >/dev/null 2>&1; then
      local tmp="${TMPDIR:-/tmp}/.proj-sync-install.$$"; rm -rf "$tmp"; mkdir -p "$tmp"
      unzip -oq "$zipf" -d "$tmp" || die "압축 해제 실패: $zipf"
      inst="$(find "$tmp" -name install.sh 2>/dev/null | head -1)"
    fi
  fi
  [ -n "$inst" ] && [ -f "$inst" ] || die "proj-sync/install.sh 를 찾지 못했습니다. proj-sync.zip 의 압축을 이 폴더에 먼저 푸세요."
  bash "$inst" || die "install.sh 실행 실패"
  SCRIPTS="$(find_scripts)" || die "설치 후에도 scripts 폴더를 찾지 못했습니다."
  echo "  ✓ 설치 완료 → Claude Code 재시작 시 /ax:* 커맨드도 보입니다."
}

# ── .env upsert (chmod 600) — ENV_FILE 변수 기준 ─────────────────────────────
env_set() {
  local key="$1" val="$2"
  [ -f "$ENV_FILE" ] && grep -vE "^${key}=" "$ENV_FILE" > "$ENV_FILE.tmp" 2>/dev/null || : > "$ENV_FILE.tmp"
  printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE.tmp"
  mv "$ENV_FILE.tmp" "$ENV_FILE"; chmod 600 "$ENV_FILE" 2>/dev/null || true
}
ensure_gitignore() {
  local d="$1"
  grep -qxF '.env' "$d/.gitignore" 2>/dev/null || echo '.env' >> "$d/.gitignore"
}
# 작성자 이름을 config.json 의 notion.author 에 기록 → notion-publish 스킬이 게시 시 작성자로 사용.
#  (config 가 아직 없으면 init 후 다시 호출되므로 조용히 skip)
save_author_to_config() {
  local name="$1" cfg="$TARGET_DIR/.proj-sync/config.json"
  [ -f "$cfg" ] || return 0
  "$PS_PY_BIN" - "$cfg" "$name" <<'PY' 2>/dev/null || true
import json,sys
p,name=sys.argv[1],sys.argv[2]
try: c=json.load(open(p,encoding="utf-8"))
except Exception: sys.exit(0)
c.setdefault("notion",{})["author"]=name
json.dump(c,open(p,"w",encoding="utf-8"),ensure_ascii=False,indent=2)
PY
}
# NAS 접속 정보(host·share·user·team_folder)를 config.nas 에 기록 (비번 제외 — 비번은 .env).
save_nas_to_config() {
  local host="$1" share="$2" user="$3" team="$4" cfg="$TARGET_DIR/.proj-sync/config.json"
  [ -f "$cfg" ] || return 0
  "$PS_PY_BIN" - "$cfg" "$host" "$share" "$user" "$team" <<'PY' 2>/dev/null || true
import json,sys
p,host,share,user,team=sys.argv[1:6]
try: c=json.load(open(p,encoding="utf-8"))
except Exception: sys.exit(0)
nas=c.setdefault("nas",{})
nas["enabled"]=True
nas["host"]=host; nas["share"]=share; nas["user"]=user; nas["team_folder"]=team
nas.setdefault("base_path","{team_folder}/{project_id}")
nas.setdefault("token_ref","env:PROJ_SYNC_NAS_TOKEN")
nas.setdefault("allowed_subnet","192.168.20.")
nas.setdefault("upload_exts",["hwp","hwpx","doc","docx","ppt","pptx","xls","xlsx","pdf","png","jpg","jpeg","gif","zip"])
json.dump(c,open(p,"w",encoding="utf-8"),ensure_ascii=False,indent=2)
PY
}

# ── 단계 함수 ────────────────────────────────────────────────────────────────
step_tools() {
  hr; echo "[도구] 사전 도구 점검 (git·curl·gh·git-lfs·python)"; hr
  bash "$SCRIPTS/setup.sh" || true
  if [ "$IS_MAC" = 1 ]; then
    [ "$(ask '누락분을 Homebrew로 자동 설치할까요? (y/N)' N)" = "y" ] && bash "$SCRIPTS/setup.sh" --install || true
  else
    echo "  (Windows/Linux는 위 안내 링크로 직접 설치 후 재실행하세요.)"
  fi
}

step_github() {
  hr; echo "[GitHub] Personal Access Token 직접 입력"; hr
  local relog=y
  if gh auth status >/dev/null 2>&1; then
    echo "  ✓ 이미 로그인됨: $(gh api user --jq .login 2>/dev/null || echo 확인됨)"
    relog="$(ask '  다른 토큰으로 다시 로그인할까요? (y/N)' N)"
  fi
  case "$relog" in y|Y) ;; *) return 0 ;; esac
  if [ -n "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ]; then
    echo "  ⚠ 환경변수 GITHUB_TOKEN/GH_TOKEN 이 있어 --with-token 이 막힙니다."
    echo "    gh는 그 토큰을 그대로 씁니다. 다른 토큰: unset GITHUB_TOKEN GH_TOKEN 후 재실행"
    return 0
  fi
  echo "  발급: https://github.com/settings/tokens  (scope: repo, read:org)"
  local pat; pat="$(ask_token '  GitHub PAT(ghp_… / github_pat_…)')"
  [ -n "$pat" ] || { echo "  (미입력 — 나중에 gh auth login)"; return 0; }
  printf '%s' "$pat" | gh auth login --with-token \
    && echo "  ✓ 로그인 성공: $(gh api user --jq .login 2>/dev/null || echo 확인됨)" \
    || echo "  ✗ 로그인 실패 — 토큰/scope 확인 후 재실행" >&2
}

step_tokens() {
  ENV_FILE="$TARGET_DIR/.env"

  hr; echo "[Slack] 봇 토큰 직접 입력 (담당자 제공값 붙여넣기)"; hr
  echo "  공용 봇 토큰입니다. 담당자에게 받은 xoxb- 값을 붙여넣으세요."
  SLACK_TOK="$(ask_token '  Slack 봇 토큰(xoxb-…, 비우면 건너뜀)')"
  if [ -n "$SLACK_TOK" ]; then
    case "$SLACK_TOK" in xoxb-*) ;; *) echo "  ⚠ xoxb- 로 시작하지 않음(그래도 저장)";; esac
    env_set PROJ_SYNC_SLACK_BOT_TOKEN "$SLACK_TOK"; echo "  ✓ .env 저장 ($ENV_FILE)"
  else echo "  (미설정)"; fi

  hr; echo "[Notion] 토큰 입력 없음"; hr
  echo "  Notion 게시는 각자의 claude.ai Notion 커넥터(개인 OAuth)가 담당합니다 — 입력할 토큰이 없습니다."

  # ── NAS 접속 정보: 사무파일(hwp/ppt/xls 등) 저장소. 주소·공유·계정·비번 모두 사용자 입력 ──
  hr; echo "[NAS] 접속 정보 입력 (사무파일 대용량 저장소)"; hr
  echo "  사무파일은 GitHub 아닌 NAS 에 저장됩니다. 본인 NAS 접속 정보를 입력하세요."
  echo "  (사용 안 하면 첫 항목에서 그냥 Enter)"
  NAS_HOST="$(ask '  NAS 주소(IP, 비우면 건너뜀)' "${NAS_HOST:-192.168.20.230}")"
  if [ -n "$NAS_HOST" ]; then
    NAS_SHARE="$(ask '  공유 폴더명' "${NAS_SHARE:-WERT-NAS}")"
    NAS_USER="$(ask '  NAS 계정 ID' "${NAS_USER:-}")"
    NAS_PW="$(ask_token '  NAS 비밀번호')"
    # 연결 테스트 + 팀 폴더 목록 선택 — Mac(mount_smbfs)·Windows(net use) 분기
    NAS_TEAM=""
    if [ -n "$NAS_USER" ] && [ -n "$NAS_PW" ]; then
      echo "  연결 확인 중…"
      local mnt="" listdir="" win_drive=""
      if [ "$IS_MAC" = 1 ] && command -v mount_smbfs >/dev/null 2>&1; then
        local enc; enc="$("$PS_PY_BIN" -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$NAS_PW" 2>/dev/null)"
        mnt="${TMPDIR:-/tmp}/.nas-onb-$$"; mkdir -p "$mnt"
        mount_smbfs "//${NAS_USER}:${enc}@${NAS_HOST}/${NAS_SHARE}" "$mnt" 2>/dev/null && listdir="$mnt"
      elif [ "$IS_WIN" = 1 ]; then
        # Windows: net use 로 가용 드라이브 마운트 (비번 URL인코딩 금지 — 원문)
        local d
        for d in Z Y X W V U; do
          if ! net use "${d}:" >/dev/null 2>&1; then
            if net use "${d}:" "\\\\${NAS_HOST}\\${NAS_SHARE}" "${NAS_PW}" /user:"${NAS_USER}" /persistent:no >/dev/null 2>&1; then
              win_drive="${d}:"; listdir="/$(printf '%s' "$d" | tr 'A-Z' 'a-z')"; break
            fi
          fi
        done
      fi
      if [ -n "$listdir" ] && [ -d "$listdir" ]; then
        echo "  ✓ NAS 연결 성공. 본인 팀 폴더를 고르세요(없으면 빈칸):"
        local folders n=0; folders="$(ls -1 "$listdir" 2>/dev/null | grep -vE '^(#recycle|recycle|@eaDir|npm-global)$')"
        printf '%s\n' "$folders" | while IFS= read -r f; do [ -n "$f" ] && { n=$((n+1)); printf '    %2d) %s\n' "$n" "$f"; }; done
        local sel; sel="$(ask '  번호 선택(직접입력=이름, 빈칸=루트)')"
        if printf '%s' "$sel" | grep -qE '^[0-9]+$'; then NAS_TEAM="$(printf '%s\n' "$folders" | sed -n "${sel}p")"
        elif [ -n "$sel" ]; then NAS_TEAM="$sel"; fi
        # 정리
        [ -n "$mnt" ] && { umount "$mnt" 2>/dev/null || diskutil unmount "$mnt" 2>/dev/null; rmdir "$mnt" 2>/dev/null; }
        [ -n "$win_drive" ] && net use "$win_drive" /delete /yes >/dev/null 2>&1
      else
        echo "  ⚠ 연결 확인 실패 또는 미지원 환경 — 입력값은 저장하니 나중에 doctor 로 점검."
        [ "$IS_WIN" = 1 ] && echo "    (Windows 비번에 특수문자가 있으면 net use 가 깨질 수 있어요 → 탐색기 수동 연결 권장)"
        [ -n "$mnt" ] && rmdir "$mnt" 2>/dev/null
      fi
    fi
    [ -n "$NAS_PW" ] && env_set PROJ_SYNC_NAS_TOKEN "$NAS_PW"
    save_nas_to_config "$NAS_HOST" "$NAS_SHARE" "$NAS_USER" "$NAS_TEAM"
    echo "  ✓ NAS 저장: $NAS_USER@$NAS_HOST/$NAS_SHARE${NAS_TEAM:+/$NAS_TEAM} (비번은 .env)"
  else echo "  (미설정 — 나중에 init 시 PS_NAS_* 또는 config 수정)"; fi

  # ── 작성자 이름: ①조직 Slack 명단 검색 선택 → ②GitHub 자동추출 → ③수동입력 ──
  #    이 한 값이 Slack 업로드 메시지 [작성자] 와 Notion 게시 작성자에 공통 사용됨.
  hr; echo "[작성자] 본인 이름 — Slack 업로드·Notion 게시의 작성자 표기에 공통 사용"; hr
  local picked gh_name guess
  # ① 조직(워크스페이스) 가입자 명단에서 이름 검색·선택 (채널 아님)
  picked="$(pick_author_from_org "$SLACK_TOK")"
  if [ -n "$picked" ]; then
    AUTHOR="$picked"; echo "  ✓ 선택됨: $AUTHOR" >&2
  else
    # ② GitHub 계정 이름 자동 추출을 기본값으로 → ③ 직접 입력
    gh_name="$(autodetect_author)"
    guess="${AUTHOR:-$gh_name}"
    [ -n "$gh_name" ] && echo "  · GitHub 계정 이름(참고): $gh_name"
    echo "  ※ 명단 선택을 건너뛰었습니다. 본인 이름을 직접 입력하세요."
    AUTHOR="$(ask '  본인 이름(예: 황한건)' "$guess")"
  fi
  if [ -n "$AUTHOR" ]; then
    env_set PROJ_SYNC_AUTHOR "$AUTHOR"; echo "  ✓ 작성자 저장: $AUTHOR (Slack·Notion 공통)"
    save_author_to_config "$AUTHOR"   # Notion 게시 스킬이 config 에서 읽도록 반영
  else echo "  (미입력 — 식별 표기 생략)"; fi

  ensure_gitignore "$TARGET_DIR"
}

step_project() {
  hr; echo "[프로젝트] 신규(init) 또는 기존 합류(clone)"; hr
  echo "  레지스트리의 기존 프로젝트:"
  bash "$SCRIPTS/registry.sh" list || echo "  (조회 실패 — gh 인증 확인. 신규는 계속 가능)"
  echo
  if [ "$(ask '진행 — (n)신규 / (e)기존 합류' n)" = "e" ]; then
    local pid; pid="$(ask '합류할 프로젝트 id')"; [ -n "$pid" ] || die "id 없음"
    bash "$SCRIPTS/registry.sh" clone "$pid"
    if [ -d "$SELF_DIR/$pid" ]; then
      TARGET_DIR="$SELF_DIR/$pid"; ENV_FILE="$TARGET_DIR/.env"
      [ -n "${SLACK_TOK:-}" ]  && env_set PROJ_SYNC_SLACK_BOT_TOKEN "$SLACK_TOK"
      [ -n "${AUTHOR:-}" ]     && { env_set PROJ_SYNC_AUTHOR "$AUTHOR"; save_author_to_config "$AUTHOR"; }
      ensure_gitignore "$TARGET_DIR"
      echo "  ✓ clone 폴더 .env·config 반영: $ENV_FILE"
      # NAS 대용량 원본도 자동으로 사용자 폴더로 받아온다 (config.nas.enabled=true 일 때만).
      #   git=문서(.md)·소스, NAS=사무파일 원본 → 합류 시 둘 다 동기화돼야 "완전한 시작".
      if [ -f "$TARGET_DIR/.proj-sync/config.json" ]; then
        echo "  · NAS 대용량 원본 받는 중… (NAS 비활성이면 자동 건너뜀)"
        ( cd "$TARGET_DIR" && PS_ROOT="$TARGET_DIR" bash "$SCRIPTS/nas_sync.sh" pull ) || \
          echo "  ⚠ NAS pull 실패/건너뜀 — 나중에 메뉴에서 다시 시도 가능 (회사망 확인)"
      fi
    fi
  else
    echo "  새 프로젝트 정보 (Enter=기본값/빈값):"
    export PS_PROJECT_ID="$(ask '  프로젝트 id (영문/숫자)' myproject)"
    export PS_PROJECT_NAME="$(ask '  프로젝트 표시명')"
    export PS_GH_ORG="$(ask '  GitHub org' ax-harness)"
    export PS_GH_REPO="$(ask '  GitHub repo 명' "$PS_PROJECT_ID")"
    export PS_SLACK_TEAM="$(ask '  Slack team id (T…, 모르면 빈칸)')"
    export PS_SLACK_CH="$(ask '  Slack channel id (C…, 모르면 빈칸)')"
    export PS_NOTION_DS="$(ask '  Notion data_source_id (안 쓰면 빈칸)')"
    PS_INIT_ROOT="$TARGET_DIR" bash "$SCRIPTS/init.sh"
    ENV_FILE="$TARGET_DIR/.env"
    [ -n "${SLACK_TOK:-}" ]  && env_set PROJ_SYNC_SLACK_BOT_TOKEN "$SLACK_TOK"
  fi
}

step_doctor()   { hr; echo "[doctor] 인증·도구·config 점검"; hr; bash "$SCRIPTS/doctor.sh" || true; }
step_slack_dl() { hr; echo "[Slack] 채널 파일 다운로드/분류"; hr; ( cd "$TARGET_DIR" && bash "$SCRIPTS/slack_download.sh" ) || true; }
step_push()     {
  hr; echo "[GitHub] 동기화 (push)"; hr
  local msg; msg="$(ask '커밋 메시지' 'proj-sync: 동기화')"
  ( cd "$TARGET_DIR" && bash "$SCRIPTS/github_push.sh" "$msg" ) || true
}
step_slack_up() {
  hr; echo "[Slack] 파일 업로드 (+작성자 식별)"; hr
  local f msg
  f="$(ask '업로드할 파일 경로')"; [ -n "$f" ] || { echo "  파일 경로 없음"; return 0; }
  [ -f "$TARGET_DIR/$f" ] || [ -f "$f" ] || { echo "  ✗ 파일을 찾을 수 없음: $f" >&2; return 0; }
  msg="$(ask '메시지(선택, @이름 멘션 가능)')"
  # 공용 봇으로 보내도 누가 올렸는지 보이도록 작성자 이름을 앞에 자동 부착
  if [ -n "$AUTHOR" ]; then
    [ -n "$msg" ] && msg="[$AUTHOR] $msg" || msg="[$AUTHOR]"
  fi
  ( cd "$TARGET_DIR" && bash "$SCRIPTS/slack_upload.sh" "$f" "$msg" ) || true
}

# ── 메인 ─────────────────────────────────────────────────────────────────────
echo "proj-sync 팀원 CLI — 작업 폴더: $SELF_DIR"
preflight          # 필요한 도구 점검·설치 안내 (필수 미설치 시 여기서 중단)
ensure_installed   # 플러그인 설치 (claude 필요)
echo "proj-sync scripts: $SCRIPTS"

TARGET_DIR="$SELF_DIR"   # 기본 작업 폴더 (clone 시 갱신)
SLACK_TOK=""; AUTHOR=""; NAS_HOST=""; NAS_SHARE=""; NAS_USER=""; NAS_PW=""; NAS_TEAM=""
# 이미 .env 에 저장된 작성자 이름이 있으면 불러오기 (재실행 시 재입력 불필요)
[ -f "$TARGET_DIR/.env" ] && AUTHOR="$(grep -E '^PROJ_SYNC_AUTHOR=' "$TARGET_DIR/.env" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"\r')"

while true; do
  echo
  hr
  echo "무엇을 할까요?     (작성자: ${AUTHOR:-미설정})"
  echo "  1) 초기 세팅 (도구→GitHub→토큰→작성자선택→프로젝트→doctor)"
  echo "  2) Slack 다운로드/분류"
  echo "  3) Slack 파일 업로드 (작성자 식별)"
  echo "  4) GitHub 동기화 (push)"
  echo "  5) doctor 재점검"
  echo "  q) 종료"
  hr
  case "$(ask '선택' 1)" in
    1) step_tools; step_github; step_tokens; step_project
       # 작성자 선택이 config 생성(init)보다 먼저라, project 후 config 에 작성자 재반영
       [ -n "$AUTHOR" ] && save_author_to_config "$AUTHOR"
       step_doctor
       echo; echo "✅ 초기 세팅 완료. 토큰: $TARGET_DIR/.env (chmod 600, .gitignore 됨)";;
    2) step_slack_dl;;
    3) step_slack_up;;
    4) step_push;;
    5) step_doctor;;
    q|Q) echo "종료."; exit 0;;
    *) echo "1~5 또는 q 를 입력하세요.";;
  esac
done
