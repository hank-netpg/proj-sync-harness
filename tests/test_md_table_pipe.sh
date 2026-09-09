#!/usr/bin/env bash
# 회귀 테스트 — 표 셀 안의 이스케이프 파이프가 열을 늘리지 않는가 (issue #29)
#
# 왜 있는가:
#   게시본만 깨지고 md 원본은 정상이라 **발견이 늦는다.** 실제로 게시 후 REST API 로 표 행을
#   전수 조회해서야 알았다. 사람 눈으로 잡히지 않는 결함이므로 검사가 저장소에 있어야 한다.
#
# 실행:  bash tests/test_md_table_pipe.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONV="$ROOT/plugin/ax/scripts/lib/md_to_notion.py"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

PY="$(command -v python3 || command -v python)"
[ -n "$PY" ] || { echo "✗ python 없음" >&2; exit 1; }
[ -f "$CONV" ] || { echo "✗ 대상 없음: $CONV" >&2; exit 1; }

pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1))
        else echo "  ✗ $1 — 기대=$2 실제=$3"; fail=$((fail+1)); fi; }

# 이슈 본문의 재현 입력 그대로 — 2열이어야 하는데 5열이 됐던 표.
cat > "$WORK/t.md" <<'MD'
| 근거 | 내용 |
|---|---|
| 방법론 p.191 | 서식 = **「방법론 표준 \| 적용여부 \| 대응물 \| 사유」** 4열 |
| 다른 근거 | 정상 내용 |
MD

"$PY" "$CONV" "$WORK/t.md" > "$WORK/out.json" 2>"$WORK/err" \
  || { echo "✗ 변환 실패: $(cat "$WORK/err")" >&2; exit 1; }

# 표 블록의 행별 셀 수 · 셀 원문을 뽑는다.
read -r WIDTHS CELLTEXT LITERALS < <("$PY" - "$WORK/out.json" <<'PY'
import json,sys
blocks=json.load(open(sys.argv[1]))
tables=[b for b in blocks if b.get("type")=="table"]
if not tables:
    print("no-table no-table no-table"); raise SystemExit
t=tables[0]["table"]
rows=[r["table_row"]["cells"] for r in t.get("children",[])]
widths=sorted({len(r) for r in rows})
def txt(cell): return "".join(x.get("plain_text") or x["text"]["content"] for x in cell)
flat=[txt(c) for r in rows for c in r]
# 마크업이 리터럴로 남았거나 백슬래시가 잔류한 셀 수
bad=sum(1 for s in flat if "**" in s or "\\" in s)
print(",".join(map(str,widths)), "|".join(flat).replace(" ","·"), bad)
PY
)

echo "── 이슈 재현 입력 (2열 표 · 셀 안에 \\| 3개)"
chk "모든 행의 열 수가 2로 일정" "2" "$WIDTHS"
chk "마크업 리터럴·백슬래시 잔존 셀 0" "0" "$LITERALS"
chk "파이프가 셀 안에 리터럴로 복원" "1" \
  "$(printf '%s' "$CELLTEXT" | grep -c '방법론·표준·|·적용여부·|·대응물·|·사유' || true)"

echo "── 일반 표는 종전대로 (회귀 없음)"
cat > "$WORK/n.md" <<'MD'
| A | B | C |
|---|---|---|
| 1 | 2 | 3 |
MD
read -r W2 _ < <("$PY" "$CONV" "$WORK/n.md" | "$PY" -c '
import json,sys
b=json.load(sys.stdin)
t=[x for x in b if x.get("type")=="table"][0]["table"]
rows=[r["table_row"]["cells"] for r in t.get("children",[])]
print(",".join(map(str,sorted({len(r) for r in rows}))), 0)
')
chk "3열 유지" "3" "$W2"

echo
echo "결과 — 통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
