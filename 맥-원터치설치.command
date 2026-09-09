#!/bin/bash
# ===========================================================================
#  proj-sync 원터치 설치 (Mac 전용)
#  ---------------------------------------------------------------------------
#  이 파일을 "더블클릭" 하면:
#    1) Homebrew(맥 자동설치 도구) 확인/설치
#    2) Git · VS Code · Python · GitHub CLI · Claude Code 확인 후 없는 것만 설치
#    3) 마지막에 proj-sync 플러그인까지 설치
#  까지 한 번에 진행합니다. 여러 번 실행해도 안전합니다.
#
#  ※ 처음엔 "확인되지 않은 개발자" 경고가 뜰 수 있어요.
#     [시스템 설정] > [개인정보 보호 및 보안] 에서 "확인 없이 열기" 를 눌러 주세요.
#     (또는 이 파일 우클릭 → "열기" → "열기")
# ===========================================================================
set -uo pipefail

# 이 스크립트가 있는 폴더로 이동 (더블클릭 시 홈에서 시작될 수 있으므로)
cd "$(dirname "$0")" || exit 1

say()  { printf '\n%s\n' "$*"; }
ok()   { printf '        OK - %s\n' "$*"; }
step() { printf '\n[%s] %s\n' "$1" "$2"; }

echo "============================================================"
echo "  proj-sync 원터치 설치를 시작합니다 (Mac)"
echo "============================================================"
echo
echo "  필요한 프로그램을 자동으로 깔아 드립니다."
echo "  중간에 암호를 물으면 '맥 로그인 암호'를 입력하세요 (화면엔 안 보임)."
echo "  인터넷이 연결돼 있어야 하며 10~20분 걸릴 수 있어요."
echo
read -r -p "  준비됐으면 Enter 를 누르세요... " _

# ---------------------------------------------------------------------------
# 0) Homebrew
# ---------------------------------------------------------------------------
step "0/6" "Homebrew(자동설치 도구) 확인 중..."
if command -v brew >/dev/null 2>&1; then
  ok "Homebrew"
else
  say "        설치를 시작합니다: Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
    say "  X  Homebrew 설치에 실패했습니다. 인터넷 연결을 확인하고 다시 실행하세요."; exit 1; }
fi
# 이 세션에서 brew 를 바로 인식하도록 PATH 반영 (Apple Silicon / Intel 모두)
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -x /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"

ensure() {  # $1=명령어  $2=brew 패키지  $3=표시이름  $4=cask(있으면)
  if command -v "$1" >/dev/null 2>&1; then ok "이미 설치됨: $3"; return; fi
  say "        설치를 시작합니다: $3"
  if [ "${4:-}" = "cask" ]; then brew install --cask "$2" || true
  else brew install "$2" || true; fi
}

# ---------------------------------------------------------------------------
step "1/6" "Git 확인 중...";        ensure git  git  "Git"
step "2/6" "VS Code 확인 중...";    ensure code visual-studio-code "VS Code" cask
step "3/6" "Python 확인 중...";     ensure python3 python "Python"
step "4/6" "GitHub CLI 확인 중... (권장)"; ensure gh gh "GitHub CLI"

# ---------------------------------------------------------------------------
step "5/6" "Claude Code 확인 중..."
if command -v claude >/dev/null 2>&1; then
  ok "이미 설치됨: Claude Code"
else
  say "        설치를 시작합니다: Claude Code"
  curl -fsSL https://claude.ai/install.sh | bash || \
    say "  ! Claude Code 자동 설치에 실패했습니다. https://claude.ai/code 에서 직접 설치 후 다시 실행하세요."
fi
# claude 설치 위치(보통 ~/.local/bin)를 이 세션 PATH 에 추가
export PATH="$HOME/.local/bin:$PATH"

# ---------------------------------------------------------------------------
step "6/6" "proj-sync 플러그인 설치 준비 중..."
if ! command -v claude >/dev/null 2>&1; then
  say "  !  Claude Code 를 아직 찾지 못했습니다."
  say "     이 창을 닫고 이 파일을 '다시 더블클릭' 하면 마무리됩니다."
  read -r -p "  Enter 를 눌러 창을 닫으세요... " _; exit 0
fi

# 플러그인 본체(install.sh) 위치: 배포본(proj-sync) 또는 레포(plugin)
PLUGDIR=""
[ -f "./proj-sync/install.sh" ] && PLUGDIR="./proj-sync"
[ -z "$PLUGDIR" ] && [ -f "./plugin/install.sh" ] && PLUGDIR="./plugin"

# 정보 입력 스크립트 위치: 배포본(proj-sync-setup.sh) 또는 레포(src/proj-sync-onboard.sh)
SETUP=""
[ -f "./proj-sync-setup.sh" ] && SETUP="./proj-sync-setup.sh"
[ -z "$SETUP" ] && [ -f "./src/proj-sync-onboard.sh" ] && SETUP="./src/proj-sync-onboard.sh"

if [ -z "$PLUGDIR" ] && [ -z "$SETUP" ]; then
  say "  !  설치 파일(proj-sync-setup.sh)을 찾지 못했습니다."
  say "     이 .command 파일은 proj-sync-setup.sh 와 '같은 폴더'에 있어야 합니다."
  read -r -p "  Enter 를 눌러 창을 닫으세요... " _; exit 1
fi

echo
echo "------------------------------------------------------------"
echo "  프로그램 설치가 끝났습니다."
echo "  이어서 '나만의 정보 입력'(GitHub 토큰 / Slack / 본인 이름 등)까지"
echo "  지금 바로 진행할 수 있습니다."
echo "------------------------------------------------------------"
echo "    Y = 지금 이어서 입력 (권장)       N = 나중에 직접 할게요"
echo
read -r -p "  지금 이어서 하시겠어요? (Y/N) [Y]: " GO

if [ "$GO" = "N" ] || [ "$GO" = "n" ] || [ -z "$SETUP" ]; then
  # --- 플러그인만 설치하고, 정보 입력은 나중에 ---
  if [ -n "$PLUGDIR" ]; then
    say "        플러그인을 설치합니다..."
    ( cd "$PLUGDIR" && bash install.sh ) || \
      echo "  !  플러그인 설치 중 문제가 있었습니다. 이 파일을 한 번 더 실행해 보세요."
  fi
  echo
  echo "============================================================"
  echo "  프로그램 설치 완료!  정보 입력만 남았어요."
  echo "============================================================"
  echo
  echo "  나중에 아래 순서로 정보(토큰/이름)를 입력하세요:"
  echo "    1) Claude Code(또는 VS Code) 껐다 켜기"
  echo "    2) VS Code 에서 이 폴더 열기 (File - Open Folder)"
  echo "    3) 터미널에 아래 한 줄 붙여넣고 Enter:"
  echo
  echo "         bash proj-sync-setup.sh"
  echo
  echo "  자세한 방법은 \"무작정따라하기.md\" 문서를 보세요."
else
  # --- 정보 입력까지 이어서: setup 실행 (플러그인 설치도 스스로 수행) ---
  echo
  echo "  잠시 후 '무엇을 할까요?' 메뉴가 나오면"
  echo "    · 지금 입력하려면  숫자  1  을 누르고 Enter"
  echo "    · 나중에 하려면     q  를 누르고 Enter"
  echo
  bash "$SETUP"
  echo
  echo "============================================================"
  echo "  모두 끝났습니다!  수고하셨어요."
  echo "============================================================"
  echo
  echo "  마지막으로 Claude Code(또는 VS Code)를 '껐다 켜면'"
  echo "  채팅창에서 /ax 명령들이 보입니다."
fi

echo
read -r -p "  Enter 를 눌러 창을 닫으세요... " _
