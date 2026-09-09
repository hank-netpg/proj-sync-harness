#!/usr/bin/env bash
# proj-sync: 사전 도구 점검·설치 도우미 (머신당 1회) — 비개발자용
#   인자 없이: 점검 + 누락 도구 설치 명령 안내
#   --install: macOS(Homebrew)에서 누락 도구 자동 설치
# config 불필요(프로젝트 밖에서도 실행 가능). 종료코드 0=모두 준비, 1=누락 있음.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

ACTION="${1:-check}"

OK=0; MISS=0
ok(){ printf '  \xe2\x9c\x93 %s\n' "$1"; OK=$((OK+1)); }
ng(){ printf '  \xe2\x9c\x97 %s\n' "$1"; MISS=$((MISS+1)); }
fix(){ printf '       \xe2\x86\xb3 %s\n' "$1"; }

case "$(uname -s)" in
  Darwin)               OS=mac;   OS_LABEL="macOS" ;;
  MINGW*|MSYS*|CYGWIN*) OS=win;   OS_LABEL="Windows (Git Bash)" ;;
  *)                    OS=linux; OS_LABEL="Linux" ;;
esac

BREW_NEEDED=""          # mac 에서 누락된 brew 패키지 모음
need_brew(){ BREW_NEEDED="$BREW_NEEDED $1"; }

# chk <라벨> <실행파일> <버전명령> <brew패키지> <win안내URL>
chk(){
  local label="$1" bin="$2" vercmd="$3" brewpkg="$4" winurl="$5"
  if command -v "$bin" >/dev/null 2>&1; then
    ok "$label: $(eval "$vercmd" 2>&1 | head -1)"
  else
    ng "$label 미설치"
    case "$OS" in
      mac)  fix "brew install $brewpkg"; need_brew "$brewpkg" ;;
      win)  fix "$winurl" ;;
      *)    fix "패키지매니저로 설치 (예: sudo apt install $brewpkg)" ;;
    esac
  fi
}

echo "=== proj-sync setup — 사전 도구 점검 ($OS_LABEL) ==="

chk "git"     git     "git --version"        git      "https://git-scm.com 에서 Git for Windows 설치(Git Bash 포함)"
chk "curl"    curl    "curl --version"       curl     "Git Bash 에 기본 포함 (없으면 Git for Windows 재설치)"
chk "GitHub CLI(gh)" gh "gh --version"       gh       "https://cli.github.com 에서 설치"
chk "Git LFS" git-lfs "git lfs version"      git-lfs  "https://git-lfs.github.com 에서 설치"

# Python 은 python3 / python 둘 중 하나면 통과
PYBIN=""
if command -v python3 >/dev/null 2>&1; then ok "Python: $(python3 --version 2>&1)"; PYBIN=python3
elif command -v python >/dev/null 2>&1; then ok "Python: $(python --version 2>&1) (python)"; PYBIN=python
else
  ng "Python 미설치"
  case "$OS" in
    mac)  fix "brew install python"; need_brew "python" ;;
    win)  fix "https://python.org 에서 설치 후 'Add to PATH' 체크" ;;
    *)    fix "sudo apt install python3" ;;
  esac
fi

# 오피스 문서(hwp/hwpx/xlsx/docx/pptx) → 마크다운 변환용 Python 라이브러리
#   PM 에이전트가 사무파일 본문을 읽으려면 변환이 필요. 누락 시 pip 로 자동 설치 시도.
PY_MISSING=""
if [ -n "$PYBIN" ]; then
  for mod in olefile openpyxl docx pptx pdfplumber; do
    "$PYBIN" -c "import $mod" >/dev/null 2>&1 || PY_MISSING="$PY_MISSING $mod"
  done
  if [ -z "$PY_MISSING" ]; then
    ok "문서 변환 라이브러리: olefile·openpyxl·docx·pptx·pdfplumber 모두 설치됨"
  else
    ng "문서 변환 라이브러리 일부 누락:$PY_MISSING (hwp/xlsx/docx/pptx/pdf 변환에 필요)"
    PYLIB_ONLY=1   # brew 대상이 아닌 pip 누락 — 인증 연결까지는 진행 가능
    # 모듈명 → pip 패키지명 매핑
    PIP_PKGS=""
    case "$PY_MISSING" in *olefile*) PIP_PKGS="$PIP_PKGS olefile";; esac
    case "$PY_MISSING" in *openpyxl*) PIP_PKGS="$PIP_PKGS openpyxl";; esac
    case "$PY_MISSING" in *docx*) PIP_PKGS="$PIP_PKGS python-docx";; esac
    case "$PY_MISSING" in *pptx*) PIP_PKGS="$PIP_PKGS python-pptx";; esac
    case "$PY_MISSING" in *pdfplumber*) PIP_PKGS="$PIP_PKGS pdfplumber";; esac
    if [ "$ACTION" = "--install" ]; then
      echo "       ↳ pip 로 자동 설치 시도:$PIP_PKGS"
      # shellcheck disable=SC2086
      "$PYBIN" -m pip install --user --quiet $PIP_PKGS 2>&1 | tail -2 && echo "       ✓ 변환 라이브러리 설치 완료" || fix "수동 설치: $PYBIN -m pip install --user$PIP_PKGS"
    else
      fix "$PYBIN -m pip install --user$PIP_PKGS  (또는 setup.sh --install)"
    fi
  fi
fi

echo "------------------------------------"
echo "결과: ✓ $OK / ✗ $MISS"

# ── 인증 연결까지 한 번에 마무리 ──
#   종전에는 여기서 "gh auth login 하고 /ax:init 하세요"로 끝나 Slack·Notion 토큰이 끝내 조회되지
#   않는 경우가 많았다(=/ax:auth 를 아무도 부르지 않음). 핵심 도구가 준비됐으면 여기서 바로 이어서 한다.
#   pip 라이브러리(pdfplumber 등)만 빠진 경우는 인증과 무관하므로 인증 단계를 건너뛰지 않는다.
CORE_MISS="$MISS"
[ "${PYLIB_ONLY:-0}" = "1" ] && CORE_MISS=$((MISS-1))
if [ "$CORE_MISS" -le 0 ]; then
  if [ "$MISS" -eq 0 ]; then
    echo "→ 모든 사전 도구 준비 완료."
  else
    echo "→ 핵심 도구 준비 완료(문서 변환 라이브러리만 누락 — 위 ↳ 명령으로 나중에 설치 가능)."
  fi
  echo
  echo "=== 인증 연결 (GitHub → Slack 봇 토큰 자동 조회) ==="

  # config 없이도 동작해야 하므로 lib 만 직접 로드 (ps_load_config 는 호출하지 않음)
  HERE_S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  . "$HERE_S/lib/config.sh" 2>/dev/null || true

  # `gh auth status` 는 계정이 여럿일 때 하나라도 토큰이 만료면 exit 1 → 실제 API 호출로 판정한다.
  GH_LOGIN="$(gh api user --jq .login 2>/dev/null)"
  if [ -z "$GH_LOGIN" ]; then
    ng "GitHub 로그인 필요(또는 활성 계정 토큰 만료)"
    fix "gh auth login   실행 후 이 커맨드를 다시 실행하세요 (그러면 Slack 봇 토큰까지 자동 조회됩니다)"
    fix "계정이 여럿이면: gh auth switch 로 활성 계정을 확인하세요"
    echo "------------------------------------"
    exit 1
  fi
  ok "GitHub: 로그인됨 ($GH_LOGIN)"

  if type ps_ensure_team_tokens >/dev/null 2>&1 && ps_ensure_team_tokens; then
    ok "Slack 봇 토큰: 확보됨"
    echo "  (저장 위치: ${PS_GLOBAL_CRED:-$HOME/.proj-sync/credentials} — 토큰 입력 불필요)"
    # Notion·Drive·Slack 개인 조회는 팀 토큰이 아니다 — 로그인한 사용자 본인의 계정 연결을 따른다.
    printf '  \xe2\x84\xb9 Notion: claude.ai Notion 커넥터(각자 1회 연결). Claude Code 에서 /mcp 로 연결 상태 확인\n'
    printf '  \xe2\x84\xb9 Google Drive: rclone(본인 Google 계정) — 사업 폴더에서 setup-remote 1회(브라우저 인증)\n'
    printf '  \xe2\x84\xb9 Slack 개인 조회(선택): claude.ai Slack 커넥터 — /mcp 로 연결 확인 (봇 발신과 별개)\n'
  else
    ng "Slack 봇 토큰 조회 실패"
    fix "ax-harness 조직 멤버십 확인:  gh api user/memberships/orgs/ax-harness --jq .state"
    fix "조직이 classic PAT 을 차단하면 fine-grained PAT 을 키체인에 등록:"
    fix "  security add-generic-password -a \"\$USER\" -s github-fine-grained-token -w '<github_pat_…>' -U"
    fix "그래도 안 되면 수동 저장:  /ax:auth  →  auth.sh set xoxb-…"
    echo "------------------------------------"
    exit 1
  fi

  echo "------------------------------------"
  echo "→ 준비 완료. 사업 폴더를 열고  /ax:init  을 실행하세요."
  exit 0
fi

# ── 누락이 있는 경우 ──
if [ "$OS" = "mac" ]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "→ Homebrew(brew)가 없습니다. 먼저 설치하세요:"
    echo '   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    echo "   설치 후  bash setup.sh --install  로 한 번에 설치할 수 있습니다."
    exit 1
  fi
  if [ "$ACTION" = "--install" ]; then
    echo "→ Homebrew 로 누락 도구 설치를 시작합니다:$BREW_NEEDED"
    # shellcheck disable=SC2086
    if brew install $BREW_NEEDED; then
      # Git LFS 는 설치 후 사용자 훅 등록(git lfs install)까지 해야 완전 충족
      if command -v git-lfs >/dev/null 2>&1; then git lfs install >/dev/null 2>&1 && echo "✓ git lfs install (훅 등록) 완료"; fi
      echo "✓ 설치 완료. 'bash setup.sh' 로 재점검하세요. 이어서 gh auth login → /ax:init"
      exit 0
    else
      echo "✗ 일부 설치 실패. 위 메시지를 확인하세요."
      exit 1
    fi
  else
    echo "→ 한 번에 설치:  brew install$BREW_NEEDED"
    echo "  또는 자동 설치:  이 커맨드에 '자동 설치해줘' 라고 하면 됩니다. (setup.sh --install)"
    exit 1
  fi
else
  echo "→ 위 ✗ 의 ↳ 링크에서 설치 후, 다시 점검하세요."
  echo "  (Windows 는 모든 스크립트를 Git Bash 에서 실행해야 합니다.)"
  exit 1
fi
