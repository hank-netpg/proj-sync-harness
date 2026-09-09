#!/usr/bin/env bash
# 회귀 테스트 — 따옴표 없는 heredoc 이 본문의 명령을 실행하지 않는가
#
# 왜 있는가:
#   2026-08-27, init.sh 가 heredoc 을 따옴표 없이(`<<PY`) 열어, 본문 파이썬 주석 안의
#   역따옴표(`rclone config`)를 **셸이 실제로 실행**했다. rclone 이 깔린 머신에서 그 출력이
#   파이썬 소스에 치환돼 SyntaxError 가 났고, config.json 이 만들어지지 않은 채 init 이
#   중단됐다. 대화형 셸에서는 rclone 이 입력을 기다려 그대로 멈췄다 (issue #38).
#
#   rclone 이 없는 머신에서는 빈 문자열로 치환돼 주석이 그대로 유효했다 — 즉 **개발자 PC 의
#   설치 구성에 따라 있다 없다 하는 결함**이라 코드만 봐서는 드러나지 않는다.
#
# 불변식:
#   따옴표 없이 연 heredoc 의 본문에는 명령치환(` · $( )이 있으면 안 된다.
#
#   「모든 heredoc 에 따옴표」로 잡지 않는 이유 — src/proj-sync-onboard.sh 의 `done <<EOF` 는
#   본문 $rows 를 **의도적으로** 확장한다(정상). 확장 결과는 셸이 재스캔하지 않으므로 안전하다.
#   그래서 매개변수 확장은 허용하고 명령치환만 막는다.
#
# 실행:  bash tests/test_heredoc_safety.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

PY="$(command -v python3 || command -v python)"
[ -n "$PY" ] || { echo "✗ python 없음" >&2; exit 1; }

pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1))
        else echo "  ✗ $1 — 기대=$2 실제=$3"; fail=$((fail+1)); fi; }

# ── 스캐너 ────────────────────────────────────────────────────────────────
# 파일을 인자로 받아 위반을 stdout 에 찍고, 마지막 줄에 VIOLATIONS=<n> 을 낸다.
cat > "$WORK/scan.py" <<'SCANNER'
import re, sys

# <<  또는 <<-  뒤의 구분자. 따옴표('/")나 백슬래시가 붙으면 "따옴표 있음"(확장 없음).
#   (?<!<)…(?!<) 로 herestring(<<<) 을 제외한다 — 없으면 <<<"x" 가 heredoc 으로 오인된다.
OPEN = re.compile(
    r'''(?<!<)<<(?!<)-?[ \t]*'''
    r'''(?:(?P<q>['"])(?P<qd>[A-Za-z_][A-Za-z0-9_]*)(?P=q)'''
    r'''|\\(?P<bd>[A-Za-z_][A-Za-z0-9_]*)'''
    r'''|(?P<ud>[A-Za-z_][A-Za-z0-9_]*))''')

def scan(path):
    viol = []
    try:
        lines = open(path, encoding='utf-8', errors='replace').read().split('\n')
    except OSError as e:
        return [(path, 0, '', 0, 'read error: %s' % e)]
    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        # 주석 줄에서는 여는 줄을 찾지 않는다 — heredoc 을 **설명하는** 주석이 있다
        # (gdrive_sync.sh). 여기서 상태를 열면 뒤 본문을 통째로 삼켜 진짜 위반을 놓친다.
        if line.lstrip().startswith('#'):
            i += 1; continue
        m = OPEN.search(line)
        if not m:
            i += 1; continue
        quoted = bool(m.group('qd') or m.group('bd'))
        delim  = m.group('qd') or m.group('bd') or m.group('ud')
        dash   = line[m.start():m.start()+3] == '<<-'
        body, j = [], i + 1
        while j < n:
            cand = lines[j].lstrip('\t') if dash else lines[j]
            if cand == delim:
                break
            body.append(lines[j]); j += 1
        if not quoted:
            for k, b in enumerate(body):
                if '`' in b or '$(' in b:
                    viol.append((path, i + 1, delim, i + 2 + k, b.strip()))
        # 본문 안에서는 새 여는 줄을 찾지 않는다 — 파이썬 소스에 들어 있는 '<<' 는 heredoc 이 아니다.
        i = j + 1
    return viol

# 대상 파일: 인자로 받거나(픽스처), 없으면 stdin 에서 한 줄에 하나씩(저장소 전수).
#   stdin 경로를 쓰는 이유 — 인자로 넘기면 파일이 늘었을 때 xargs 가 여러 번 나뉘어 돌고
#   VIOLATIONS 줄이 여러 개 나온다. 한 프로세스에서 세야 합계가 맞는다.
paths = sys.argv[1:] or [ln for ln in sys.stdin.read().split('\n') if ln]

all_v = []
for p in paths:
    all_v.extend(scan(p))
for path, oln, delim, bln, text in all_v:
    print("  ↳ %s:%d 따옴표 없는 <<%s 의 본문 %d행에 명령치환: %s" % (path, oln, delim, bln, text[:70]))
print("VIOLATIONS=%d" % len(all_v))
SCANNER

run_scan() { "$PY" "$WORK/scan.py" "$@"; }
count_of() { printf '%s\n' "$1" | sed -n 's/^VIOLATIONS=//p'; }

echo "[1] 저장소 전체에 위반 heredoc 이 없는가"

# git ls-files 로 모은다 — 동기화 도구가 만드는 "이름 2.sh" 사본(.gitignore:22)이 자동으로 빠지고,
# 목록이 결정론적이다. git 이 없으면 find 로 폴백한다.
#   목록은 배열이 아니라 파일에 담는다 — mapfile 은 bash 4+ 이고 macOS 기본 bash 는 3.2 다.
LIST="$WORK/sh.list"
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  (cd "$ROOT" && git ls-files -- '*.sh') | sed "s|^|$ROOT/|" > "$LIST"
else
  find "$ROOT" -name '*.sh' -not -path '*/.git/*' -not -name '* [2-9].sh' > "$LIST"
fi
NSH="$(grep -c . "$LIST" || true)"
echo "     대상 $NSH 파일"
[ "${NSH:-0}" -gt 0 ] || { echo "  ✗ .sh 를 하나도 못 찾음(스캔 무효)"; exit 1; }

OUT="$("$PY" "$WORK/scan.py" < "$LIST")"
printf '%s\n' "$OUT" | grep '↳' || true
chk "위반 0건" "0" "$(count_of "$OUT")"

echo "[2] 대조군 — 스캐너가 실제로 잡는가"

# 스캐너가 조용히 죽거나 정규식이 어긋나면 [1] 이 "0건"으로 **통과해 버린다.**
# 합성 픽스처로 검출 능력을 매번 증명한다.
cat > "$WORK/bad_backtick.sh" <<'FIXTURE'
#!/usr/bin/env bash
python3 - "$CFG" <<PY
# remote 는 머신당 1회 `rclone config` 로 만든다.
cfg = {}
PY
FIXTURE
chk "역따옴표를 잡는다" "1" "$(count_of "$(run_scan "$WORK/bad_backtick.sh")")"

cat > "$WORK/bad_dollar.sh" <<'FIXTURE'
#!/usr/bin/env bash
cat <<EOF
today is $(date +%F)
EOF
FIXTURE
chk "\$( ) 를 잡는다" "1" "$(count_of "$(run_scan "$WORK/bad_dollar.sh")")"

# 따옴표를 씌우면 같은 본문이 통과해야 한다 — 「전부 위반」으로 세는 스캐너가 아님을 보인다.
cat > "$WORK/good_quoted.sh" <<'FIXTURE'
#!/usr/bin/env bash
python3 - "$CFG" <<'PY'
# remote 는 머신당 1회 `rclone config` 로 만든다.
cfg = {}
PY
FIXTURE
chk "따옴표를 씌우면 통과한다" "0" "$(count_of "$(run_scan "$WORK/good_quoted.sh")")"

# 의도된 확장(<<EOF + $rows)은 막지 않는다 — onboard.sh 가 실제로 쓰는 형태.
cat > "$WORK/good_param.sh" <<'FIXTURE'
#!/usr/bin/env bash
while IFS='|' read -r a b; do :; done <<EOF
$rows
EOF
FIXTURE
chk "의도된 매개변수 확장은 통과한다" "0" "$(count_of "$(run_scan "$WORK/good_param.sh")")"

echo "[3] issue #38 지목 앵커 — init.sh"

# 이름으로 남긴다. [1] 은 저장소 전체를 보지만, 이 결함이 어디였는지는 여기서만 알 수 있다.
INIT="$ROOT/plugin/ax/scripts/init.sh"
chk "config 생성 heredoc 이 <<'PY' 다" "1" \
  "$(grep -c "^\"\$PS_PY\" - \"\$CFG\" <<'PY'\$" "$INIT" || true)"
chk "따옴표 없는 <<PY 가 남아 있지 않다" "0" \
  "$(grep -cE '<<PY[[:space:]]*$' "$INIT" || true)"
chk "init.sh 단독 스캔 위반 0건" "0" "$(count_of "$(run_scan "$INIT")")"

echo "[4] 정상 코드를 막지 않는가 — onboard.sh 의 의도된 <<EOF"

ONB="$ROOT/src/proj-sync-onboard.sh"
if [ -f "$ONB" ]; then
  chk "onboard.sh 위반 0건" "0" "$(count_of "$(run_scan "$ONB")")"
else
  echo "  ℹ src/proj-sync-onboard.sh 없음 — 건너뜀"
fi

echo "------------------------------------"
echo "결과: ✓ $pass / ✗ $fail"
[ "$fail" -eq 0 ]
