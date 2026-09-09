#!/usr/bin/env bash
# build.sh — proj-sync.zip (팀원 배포본) 빌드 (평탄화 구조)
#   압축을 풀면 최상위에 바로 보이도록 구성:
#     proj-sync-setup.sh   (실행 파일)
#     GUIDE.md             (사용 가이드)
#     proj-sync/           (플러그인 본체: install.sh + .claude-plugin + proj-sync/)
#
#   소스:  src/proj-sync-onboard.sh  →  zip 최상위 proj-sync-setup.sh 로 이름 변경 포함
#          GUIDE.md
#          플러그인 본체 = 레포 내 plugin/  (자기완결 — 외부 사본을 쓰지 않는다)
# 사용:  bash build.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/src/proj-sync-onboard.sh"
GUIDE="$HERE/GUIDE.md"
MANUAL="$HERE/MANUAL.md"
# 플러그인 본체는 **레포 내 plugin/ 뿐**이다.
# 종전에는 없으면 ~/.claude/marketplaces-local/ax-harness 로 폴백했는데, 그곳은 머신에 따라
# 몇 달 전 zip 설치본이 남아 있는 자리다 — 조용히 구버전을 배포본에 말아 넣는 길이었다.
WROOT="$HERE/plugin"
OUT="$HERE/proj-sync.zip"

[ -f "$SRC" ]   || { echo "✗ 소스 없음: $SRC" >&2; exit 1; }
[ -f "$GUIDE" ] || { echo "✗ GUIDE.md 없음" >&2; exit 1; }
[ -d "$WROOT/ax/scripts" ] || { echo "✗ 플러그인 본체 없음: $WROOT" >&2; exit 1; }
command -v zip >/dev/null || { echo "✗ zip 필요" >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
STAGE="$TMP/proj-sync"; mkdir -p "$STAGE"

# 1) 사용자 실행 파일·가이드 = 최상위 (영문명)
cp "$SRC"   "$STAGE/proj-sync-setup.sh"
cp "$GUIDE" "$STAGE/GUIDE.md"
[ -f "$MANUAL" ] && cp "$MANUAL" "$STAGE/MANUAL.md"

# 2) 플러그인 본체 = proj-sync/ (install.sh 와 marketplace.json 이 같은 폴더에 있어야 함)
mkdir -p "$STAGE/proj-sync"
cp "$WROOT/install.sh"        "$STAGE/proj-sync/install.sh"
cp "$WROOT/INSTALL.md"        "$STAGE/proj-sync/INSTALL.md" 2>/dev/null || true
cp "$WROOT/README.md"         "$STAGE/proj-sync/README.md"  2>/dev/null || true
cp "$WROOT/.gitignore"        "$STAGE/proj-sync/.gitignore" 2>/dev/null || true
cp -R "$WROOT/.claude-plugin" "$STAGE/proj-sync/.claude-plugin"
cp -R "$WROOT/ax"             "$STAGE/proj-sync/ax"
rm -rf "$STAGE/proj-sync/ax/.git"
find "$STAGE" -name '.DS_Store' -delete 2>/dev/null || true

# 3) LF 강제 (Windows 깨짐 방지) — 텍스트 스크립트
for f in "$STAGE/proj-sync-setup.sh" "$STAGE/proj-sync/install.sh"; do
  [ -f "$f" ] && perl -i -pe 's/\r$//' "$f" 2>/dev/null || true
done

# 4) zip 생성 (압축 풀면 proj-sync/ 한 폴더가 생기고, 그 안이 평탄)
rm -f "$OUT"
( cd "$TMP" && zip -rqX "$OUT" proj-sync -x '*.DS_Store' )

# 5) 검증
bash -n "$STAGE/proj-sync-setup.sh" || { echo "✗ setup.sh 문법 오류" >&2; exit 1; }
unzip -tq "$OUT" >/dev/null || { echo "✗ zip 무결성 오류" >&2; exit 1; }
VER="$(grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' "$WROOT/ax/.claude-plugin/plugin.json" 2>/dev/null | head -1)"
echo "✅ 빌드 완료: $OUT"
echo "   plugin v$VER · $(wc -c < "$OUT") bytes"
echo "   압축 풀면: proj-sync/ → (proj-sync-setup.sh · GUIDE.md · proj-sync/)"
echo "   팀원: zip 압축 풀고 → 그 폴더에서  bash proj-sync-setup.sh"
