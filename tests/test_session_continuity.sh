#!/usr/bin/env bash
# 회귀 테스트 — 세션 연속성(SessionStart 맥락 주입 · history 미갱신 경고)
#
# 왜 있는가:
#   훅은 **조용히 안 되는 것**이 가장 나쁜 실패다. 세션 시작을 막지 않으려고 모든 실패를
#   삼키게 만들었기 때문에(exit 0), 망가져도 아무도 모른다. 그래서 검사가 저장소에 있어야 한다.
#
#   특히 지키는 것 2가지:
#     - `.proj-sync` 가 없는 곳에서 **침묵**하는가 (우산 저장소·임의 디렉토리에서 떠들면 안 된다)
#     - 주간보고와 digest 가 **같은 facts()** 를 쓰는가 (갈리면 둘이 서로 다른 말을 한다)
#
# 실행:  bash tests/test_session_continuity.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AX="$ROOT/plugin/ax"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

PY="$(command -v python3 || command -v python)"
[ -n "$PY" ] || { echo "✗ python 없음" >&2; exit 1; }

pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1))
        else echo "  ✗ $1 — 기대=$2 실제=$3"; fail=$((fail+1)); fi; }

# ── 픽스처: 최소 사업 저장소 ──────────────────────────────────────
P="$WORK/proj"
mkdir -p "$P/.proj-sync" "$P/revision" "$P/slack-files" "$P/reference/drafts"
cat > "$P/.proj-sync/config.json" <<'JSON'
{"version":1,"project":{"id":"t","name":"테스트 사업"},"lifecycle":{"phase":"수행중"},
 "wbs":{"base_date":"2026-08-01","profile":"",
   "tasks":[{"wbs":"1.1.1","name":"지난 과제","level":3,"status":"진행중","due":"2026-08-10","owner":"홍길동"},
            {"wbs":"1.1.2","name":"끝난 과제","level":3,"status":"완료","due":"2026-08-10"}],
   "milestones":[]}}
JSON
cat > "$P/revision/history.md" <<'MD'
# Revision History

## 2026-08-20

○ **첫 항목 제목** — 이 줄이 요약에 떠야 한다
- 세부 조각은 제목 자리에 오면 안 된다
○ ~~⚠ **닫힌 항목** — 취소선이 그어졌으니 미해결이 아니다~~
○ ⚠ **열린 항목** — 이건 미해결로 잡혀야 한다
MD
( cd "$P" && git init -q && git config user.email t@t && git config user.name 테스터 \
  && git add -A && git commit -qm "초기 커밋" ) >/dev/null 2>&1

export PROJ_SYNC_REPORT_DATE=2026-08-26

echo "[1] digest 가 사업 저장소에서 맥락을 낸다"
D="$(cd "$P" && "$PY" "$AX/scripts/build_report.py" --digest 2>/dev/null)"
case "$D" in *"테스트 사업"*) echo "  ✓ 사업명 포함"; pass=$((pass+1));;
             *) echo "  ✗ 사업명 없음"; fail=$((fail+1));; esac
case "$D" in *"첫 항목 제목"*) echo "  ✓ ○ 항목 제목을 쓴다(세부 조각 아님)"; pass=$((pass+1));;
             *) echo "  ✗ 항목 제목 누락"; fail=$((fail+1));; esac
case "$D" in *"세부 조각"*) echo "  ✗ 세부 조각이 제목 자리에 왔다"; fail=$((fail+1));;
             *) echo "  ✓ 세부 조각이 제목 자리에 오지 않음"; pass=$((pass+1));; esac
case "$D" in *"열린 항목"*) echo "  ✓ 미해결(⚠)을 잡는다"; pass=$((pass+1));;
             *) echo "  ✗ 미해결 누락"; fail=$((fail+1));; esac
UNRES="$(printf '%s' "$D" | sed -n '/^\[미해결/,/^\[/p')"
case "$UNRES" in *"닫힌 항목"*) echo "  ✗ 취소선(~~) 항목을 미해결로 잡았다"; fail=$((fail+1));;
                 *) echo "  ✓ 취소선 항목은 미해결에서 제외한다"; pass=$((pass+1));; esac
case "$D" in *"닫힌 항목"*) echo "  ✗ 취소선 항목이 revision 제목에 남았다"; fail=$((fail+1));;
             *) echo "  ✓ 취소선 항목은 revision 제목에서도 빠진다"; pass=$((pass+1));; esac
case "$D" in *"1.1.1"*) echo "  ✓ 지연 과제를 잡는다"; pass=$((pass+1));;
             *) echo "  ✗ 지연 누락"; fail=$((fail+1));; esac
case "$D" in *"1.1.2"*) echo "  ✗ 완료 과제를 지연으로 잡았다"; fail=$((fail+1));;
             *) echo "  ✓ 완료 과제는 지연에서 제외"; pass=$((pass+1));; esac

echo "[2] .proj-sync 없는 곳에서는 침묵한다"
mkdir -p "$WORK/bare"
OUT="$(cd "$WORK/bare" && "$PY" "$AX/scripts/build_report.py" --digest 2>/dev/null)"; RC=$?
chk "digest 출력 0바이트" "0" "$(printf '%s' "$OUT" | wc -c | tr -d ' ')"
chk "digest 종료코드 0" "0" "$RC"
HOUT="$(cd "$WORK/bare" && bash "$AX/hooks/context_digest.sh" 2>/dev/null)"; HRC=$?
chk "훅 출력 0바이트" "0" "$(printf '%s' "$HOUT" | wc -c | tr -d ' ')"
chk "훅 종료코드 0" "0" "$HRC"

echo "[3] 훅이 유효한 SessionStart JSON 을 낸다"
J="$(cd "$P" && bash "$AX/hooks/context_digest.sh" 2>/dev/null)"
EV="$(printf '%s' "$J" | "$PY" -c 'import json,sys
try: print(json.load(sys.stdin)["hookSpecificOutput"]["hookEventName"])
except Exception: print("PARSE-FAIL")' 2>/dev/null)"
chk "hookEventName=SessionStart" "SessionStart" "$EV"
ASCII="$(printf '%s' "$J" | LC_ALL=C grep -qP '[^\x00-\x7F]' 2>/dev/null && echo no || echo yes)"
chk "JSON 이 순수 ASCII(로케일 무관)" "yes" "$ASCII"

echo "[4] 상한을 지킨다"
{ echo; echo "## 2026-08-25"; for i in $(seq 1 400); do echo "○ **항목 $i** — 아주 긴 설명을 반복해서 붙인다 $i"; done; } >> "$P/revision/history.md"
BIG="$(cd "$P" && "$PY" "$AX/scripts/build_report.py" --digest 2>/dev/null | wc -c | tr -d ' ')"
chk "digest ≤ 4100바이트 (실제 $BIG)" "yes" "$([ "$BIG" -le 4100 ] && echo yes || echo no)"

echo "[5] yaml 없어도 죽지 않는다 (훅 제1원칙)"
mkdir -p "$WORK/noyaml" && printf 'raise ImportError("simulated")\n' > "$WORK/noyaml/yaml.py"
NY="$(cd "$P" && PYTHONPATH="$WORK/noyaml" "$PY" "$AX/scripts/build_report.py" --digest 2>/dev/null)"; NRC=$?
chk "yaml 부재 시 종료코드 0" "0" "$NRC"
case "$NY" in *"테스트 사업"*) echo "  ✓ 전제 외 나머지는 정상 출력"; pass=$((pass+1));;
              *) echo "  ✗ yaml 부재 시 출력이 비었다"; fail=$((fail+1));; esac

echo "[6] history 미갱신 경고가 사람 변경에만 뜬다"
# [4] 가 history.md 를 부풀려 놓았다 — 커밋해서 트리를 깨끗이 한 뒤 분기를 본다.
# (안 하면 history.md 자체가 "사람 변경"으로 잡혀 기계적 동기화 케이스가 오염된다)
( cd "$P" && git add -A && git commit -qm "픽스처 정리" ) >/dev/null 2>&1
BLOCK="$(sed -n '/revision\/history.md 미갱신 경고/,/^fi$/p' "$AX/scripts/github_push.sh")"
[ -n "$BLOCK" ] || { echo "  ✗ 경고 블록을 찾지 못했다"; fail=$((fail+1)); }
warn_out() { ( cd "$P" && git reset -q && eval "$1" && git add -A \
                && PS_ROOT="$P" bash -c "$BLOCK" 2>&1 ) ; }
M="$(warn_out 'echo x >> slack-files/a.txt')"
chk "기계적 동기화(slack-files)만 → 침묵" "0" "$(printf '%s' "$M" | grep -c 'history.md 에 오늘')"
H="$(warn_out 'echo x >> reference/drafts/설계.md')"
chk "사람 변경 + 오늘 항목 없음 → 경고" "1" "$(printf '%s' "$H" | grep -c 'history.md 에 오늘')"
chk "경고에 한글 경로가 이스케이프 없이 나온다" "1" "$(printf '%s' "$H" | grep -c '설계.md')"
T="$(warn_out "printf '\n## %s\n- 오늘 한 일\n' \"\$(date +%Y-%m-%d)\" >> revision/history.md")"
chk "오늘 항목 있으면 → 침묵" "0" "$(printf '%s' "$T" | grep -c 'history.md 에 오늘')"

echo "[7] .gitignore 에 개인 설정이 제외된다"
chk "템플릿에 settings.local.json" "1" "$(grep -c '^\.claude/settings\.local\.json$' "$AX/templates/gitignore.template")"
chk "scaffold 가 기존 사업에도 소급(멱등)" "1" "$(grep -c 'claude/settings\\\.local\\\.json' "$AX/scripts/lib/scaffold.sh")"

echo "------------------------------------"
echo "결과: ✓ $pass / ✗ $fail"
[ "$fail" -eq 0 ]
