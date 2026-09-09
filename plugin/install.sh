#!/usr/bin/env bash
# proj-sync 원클릭 설치 — 압축을 푼 이 폴더에서 실행하면 끝.
#   마켓플레이스 등록 + 플러그인 설치를 알아서 처리하며, 여러 번 실행해도 안전합니다.
# 사용: bash install.sh   (터미널에서 직접 실행 — Windows 는 Git Bash)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v claude >/dev/null 2>&1 || {
  echo "[proj-sync] Claude Code CLI(claude)를 찾지 못했습니다. Claude Code 를 먼저 설치/실행하세요."; exit 1; }
[ -f "$DIR/.claude-plugin/marketplace.json" ] || {
  echo "[proj-sync] marketplace.json 을 찾지 못했습니다. 압축을 올바르게 풀었는지 확인하세요 (이 스크립트는 압축 최상위 폴더에 있어야 합니다)."; exit 1; }

echo "[proj-sync] 설치를 시작합니다…"

# 1) 안정 위치로 복사 — 나중에 프로젝트 폴더/압축본을 지워도 동작하도록
#    ⚠️ 덮어쓰기(cp -R)만 하면 **구 레이아웃이 그대로 남아 섞인다**. 실제로 플러그인 폴더명이
#    proj-sync → ax 로 바뀐 뒤에도 옛 `proj-sync/`(구버전)가 남아, 같은 위치에 두 버전이
#    공존했다. 안정 위치는 zip 사본일 뿐이므로 **비우고 새로 채운다**.
STABLE="$HOME/.claude/marketplaces-local/ax-harness"
rm -rf "$STABLE" 2>/dev/null || true
mkdir -p "$STABLE"
cp -R "$DIR/." "$STABLE/" 2>/dev/null || true
rm -rf "$STABLE/.git" 2>/dev/null || true

# 2) 마켓플레이스 등록 (이미 있으면 갱신)
if claude plugin marketplace list 2>/dev/null | grep -qi 'ax-harness'; then
  claude plugin marketplace update ax-harness >/dev/null 2>&1 || true
else
  claude plugin marketplace add "$STABLE" || {
    echo "[proj-sync] 마켓플레이스 등록 실패."; exit 1; }
fi

# 3) 플러그인 설치 (이미 있으면 갱신) — 플러그인명: ax (구 proj-sync)
if claude plugin list 2>/dev/null | grep -qi 'ax@ax-harness'; then
  claude plugin update ax@ax-harness || true
else
  claude plugin install ax@ax-harness || {
    echo "[proj-sync] 플러그인 설치 실패."; exit 1; }
fi

echo
echo "✅ 설치 완료!"
echo "   1) Claude Code 를 재시작하세요 (그래야 /ax:* 커맨드가 보입니다)."
echo "   2) 첫 사용:  /ax:setup  →  /ax:start (기존 합류) 또는 /ax:init (신규)"
echo "   3) 에이전트:  @agent-ax:pm (사업관리) · @agent-ax:pl (문서작성)"
