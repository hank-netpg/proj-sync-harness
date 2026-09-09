#!/usr/bin/env bash
# 회귀 테스트 — 게시 경로가 텍스트를 조용히 훼손하지 않는가
#
# 두 가지를 지킨다:
#
#   1) 살균(sanitize) — 자료가 Slack·Notion·웹에서 **복사돼** 들어오면서 제로폭·BOM·
#      bidi 문자가 딸려 온다. 눈에 안 보이면서 글자수·검색·정렬·중복제거를 어긋나게
#      한다. 제목이 같아 보여도 다른 키가 되어 게시 멱등이 깨진다(#21 과 같은 부류).
#
#   2) 구조 보존 — md_to_notion 의 헤딩 정규식이 `#{1,3}` 이라 **h4 이상이 헤딩으로
#      인식조차 되지 않고** 문단으로 떨어져, 게시본에 `#### 제목` 이 리터럴로 남았다.
#        실측(2026-08-28): 제안서 본문 370파일 중 168파일 · md헤딩 1,406개 중 368개(26.2%)
#      계층은 3단까지만 있으므로 h4+ 는 heading_3 으로 접는다 — 제목이라는 사실은 지킨다.
#
# 축은 실측으로 골랐다. 각주(footnote)는 산출물 401파일에서 **0건**이라 검사하지 않는다 —
# 상시 0인 검사는 통과의 뜻을 흐린다.
#
# 실행:  bash tests/test_structure_gate.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT/plugin/ax/scripts/lib"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

PY="$(command -v python3 || command -v python)"
[ -n "$PY" ] || { echo "✗ python 없음" >&2; exit 1; }

pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1))
        else echo "  ✗ $1 — 기대=$2 실제=$3"; fail=$((fail+1)); fi; }

echo "[1] 살균 — 보이지 않는 문자를 걷어내는가"

# 픽스처는 셸이 아니라 파이썬으로 만든다 — 제로폭 문자를 셸 리터럴로 두면
# 편집기·복사 과정에서 사라져 테스트가 조용히 무력화된다.
"$PY" - "$WORK" <<'PY'
import os, sys
w = sys.argv[1]
dirty = ("회의​록 ﻿제목­입니다\n"
         "‮뒤집힘‬ 정상\n"
         "⁠붙임‍1\n")
open(os.path.join(w, "dirty.md"), "w", encoding="utf-8").write(dirty)
open(os.path.join(w, "clean.md"), "w", encoding="utf-8").write(
    "회의록 제목입니다\n뒤집힘 정상\n붙임1\n")
PY

R="$("$PY" - "$LIB" "$WORK" <<'PY'
import sys, os
sys.path.insert(0, sys.argv[1]); w = sys.argv[2]
from sanitize import scrub, scan
dirty = open(os.path.join(w, "dirty.md"), encoding="utf-8").read()
clean = open(os.path.join(w, "clean.md"), encoding="utf-8").read()
print(len(scan(dirty)))                      # 검출 종류 수
print("EQ" if scrub(dirty) == clean else "NE")   # 살균 결과 == 기대
print("ID" if scrub(scrub(dirty)) == scrub(dirty) else "NO")   # 멱등
print("KEEP" if scrub(clean) == clean else "CHANGED")          # 깨끗한 글 무변경
print(len(dirty) - len(scrub(dirty)))         # 제거된 문자 수
PY
)"
# shellcheck disable=SC2086  # 단어분리가 목적 — 파이썬이 한 줄에 하나씩 낸 값을 위치인자로 받는다
set -- $R
# 픽스처에 심은 7종: ZWSP · ZWJ · WJ · BOM · soft hyphen · PDF · RLO
chk "보이지 않는 문자 7종을 검출한다" "7" "$1"
chk "살균 결과가 기대 텍스트와 같다"    "EQ" "$2"
chk "살균은 멱등이다"               "ID" "$3"
chk "깨끗한 텍스트는 건드리지 않는다"   "KEEP" "$4"
chk "제거된 문자 수가 검출 수와 맞는다" "7" "$5"

echo "[2] 헤딩 계층 — h4+ 가 문단으로 떨어지지 않는가 (게시 결함 앵커)"

T="$("$PY" - "$LIB" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import md_to_notion as M
md = "# 1단\n## 2단\n### 3단\n#### 4단\n##### 5단\n###### 6단\n본문.\n"
b = M.md_to_blocks(md)
print(sum(1 for x in b if x["type"].startswith("heading_")))   # 헤딩 블록 수
# 문단에 '#' 가 리터럴로 남았는가
lit = 0
for x in b:
    if x["type"] == "paragraph":
        t = "".join(r.get("text", {}).get("content", "") for r in x["paragraph"]["rich_text"])
        if t.strip().startswith("#"): lit += 1
print(lit)
print(",".join(x["type"] for x in b if x["type"].startswith("heading_")))
PY
)"
# shellcheck disable=SC2086  # 단어분리가 목적 — 파이썬이 한 줄에 하나씩 낸 값을 위치인자로 받는다
set -- $T
chk "md 헤딩 6개가 모두 heading 블록이 된다" "6" "$1"
chk "문단에 남은 리터럴 '#' 0건"            "0" "$2"
chk "h4~h6 은 heading_3 으로 접힌다" \
    "heading_1,heading_2,heading_3,heading_3,heading_3,heading_3" "$3"

# 소스 불변식 — 정규식이 `#{1,3}` 으로 되돌아가면 여기서 걸린다.
chk "헤딩 정규식이 #{1,6} 이다"     "1" "$(grep -c '\^(#{1,6})' "$LIB/md_to_notion.py" || true)"
chk "#{1,3} 이 남아 있지 않다"       "0" "$(grep -c '\^(#{1,3})' "$LIB/md_to_notion.py" || true)"

echo "[3] 구조 게이트 — 소실을 실제로 잡는가 (대조군)"

G="$("$PY" - "$LIB" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from structure_gate import check_blocks
import md_to_notion as M
md = "# 제목\n## 절\n#### 소절\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```py\nx=1\n```\n"
ok = M.md_to_blocks(md)
print(len(check_blocks(md, ok)))                       # 정상 변환 → 0

# 결함 주입 ①: 헤딩 하나를 문단으로 떨어뜨린다
bad = [b for b in ok if not (b["type"] == "heading_3" and "소절" in str(b))]
bad.append({"object": "block", "type": "paragraph",
            "paragraph": {"rich_text": [{"type": "text", "text": {"content": "#### 소절"}}]}})
codes = sorted({c for c, _ in check_blocks(md, bad)})
print(",".join(codes))

# 결함 주입 ②: 표를 통째로 없앤다
notbl = [b for b in ok if b["type"] != "table"]
print(",".join(sorted({c for c, _ in check_blocks(md, notbl)})))

# 결함 주입 ③: 코드블록을 없앤다
nocode = [b for b in ok if b["type"] != "code"]
print(",".join(sorted({c for c, _ in check_blocks(md, nocode)})))

# 코드블록 **안의** '#' 주석과 '|' 는 구조로 세지 않는다
md2 = "# 진짜제목\n\n```sh\n# 이건 주석\n| not | a | table |\n```\n"
print(len(check_blocks(md2, M.md_to_blocks(md2))))
PY
)"
# shellcheck disable=SC2086  # 단어분리가 목적 — 파이썬이 한 줄에 하나씩 낸 값을 위치인자로 받는다
set -- $G
chk "정상 변환은 통과(위반 0)"        "0" "$1"
chk "헤딩 소실·흡수를 잡는다"          "heading_absorbed,heading_lost" "$2"
chk "표 소실을 잡는다"               "table_lost" "$3"
chk "코드블록 소실을 잡는다"           "code_lost" "$4"
chk "코드블록 안의 #·| 는 구조로 세지 않는다" "0" "$5"

echo "[4] 실제 문서 회귀 — 저장소 한글 문서가 전부 통과하는가"

N=0; BAD=0
for f in "$ROOT/README.md" "$ROOT/CHANGELOG.md" "$ROOT/GUIDE.md" \
         "$ROOT/docs/notion/overview.md" "$ROOT/docs/notion/onboarding-guide.md" \
         "$ROOT/plugin/ax/MANUAL.md" "$ROOT/plugin/ax/README.md"; do
  [ -f "$f" ] || continue
  N=$((N+1))
  out="$("$PY" "$LIB/structure_gate.py" "$f" 2>&1)" || { BAD=$((BAD+1)); echo "     ↳ $(basename "$f"): $out"; }
done
[ "$N" -gt 0 ] || { echo "  ✗ 대상 문서를 하나도 못 찾음(검사 무효)"; fail=$((fail+1)); }
chk "게이트 위반 문서 0건 ($N 파일 검사)" "0" "$BAD"

echo "------------------------------------"
echo "결과: ✓ $pass / ✗ $fail"
[ "$fail" -eq 0 ]
