#!/usr/bin/env bash
# 회귀 테스트 — Notion 게시 경로 정규화 ps_nfc (issue #21 · #22 의 공통 뿌리)
# (스윕 계수·결과확인 2부는 v1.21.0 에서 REST 스크립트와 함께 삭제 — 불변식은 notion_plan.py + test_notion_plan.sh 가 승계)
#
# 왜 있는가:
#   #22 는 1.13.3 에서 보고되고 1.16.0 까지 같은 코드로 남았다. 이 계열의 결함은
#   **로그가 전부 성공으로 보이는** 형태라 사람 눈으로 잡히지 않는다.
#     · 중복 게시(#21) — 로그는 전부 ✅
#     · 고아 오탐(#22) — 게시 성공 직후 같은 문서가 아카이브
#     · 허위 보고(#31②) — 로그는 107건 아카이브, 실측 0건
#   전부 「했다고 말한 것과 실제가 다른」 결함이므로 실행 가능한 검사가 저장소에 있어야 한다.
#
# 실행:  bash tests/test_notion_paths.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/plugin/ax/scripts/lib/config.sh"

pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1))
        else echo "  ✗ $1 — 기대=$2 실제=$3"; fail=$((fail+1)); fi; }

# ── 1부: ps_nfc (lib/config.sh) ──────────────────────────────
. "$LIB"
set +eu

PY="${PS_PY:-$(command -v python3 || command -v python)}"
[ -n "$PY" ] || { echo "✗ python 없음" >&2; exit 1; }

NFC_NAME="$("$PY" -c 'import unicodedata;print(unicodedata.normalize("NFC","완료보고서.md"))')"
NFD_NAME="$("$PY" -c 'import unicodedata;print(unicodedata.normalize("NFD","완료보고서.md"))')"

echo "── ps_nfc: 정규화 (issue #21·#22 의 공통 뿌리)"
chk "NFD 와 NFC 는 애초에 다른 바이트열" "다름" \
  "$([ "$NFD_NAME" != "$NFC_NAME" ] && echo 다름 || echo 같음)"
chk "NFD 입력 → NFC 출력"   "$NFC_NAME" "$(ps_nfc "$NFD_NAME")"
chk "NFC 입력 → 그대로"     "$NFC_NAME" "$(ps_nfc "$NFC_NAME")"
chk "빈 입력 → 빈 출력"     ""          "$(ps_nfc "")"
chk "영문은 불변"           "a/b/c.md"  "$(ps_nfc "a/b/c.md")"
# 핵심 — 같은 파일의 두 표기가 **같은 키**로 모인다. 이것이 중복 게시·고아 오탐을 동시에 막는다.
chk "NFD·NFC 가 같은 키로 수렴" "같음" \
  "$([ "$(ps_nfc "$NFD_NAME")" = "$(ps_nfc "$NFC_NAME")" ] && echo 같음 || echo 다름)"

echo "────────────────────────────"
echo "통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
