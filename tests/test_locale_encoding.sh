#!/usr/bin/env bash
# 회귀 테스트 — 로케일이 UTF-8 이 아닌 PC 에서 한글이 깨진 채 발신되지 않는가
#
# 왜 있는가:
#   2026-08-26, 한국어 Windows(cp949)에서 돌린 동기화가 Slack 에 "동기화 완료" 대신
#   "????ȭ ?Ϸ?" 를 올렸다. Python 의 print() 가 sys.stdout.encoding(= 로케일 기본)으로
#   인코딩하는데, 그 바이트를 그대로 `charset=utf-8` 로 보냈기 때문이다.
#   mac/linux 는 로케일 기본이 UTF-8 이라 **같은 코드가 정상 동작했다** — 그래서 이 결함은
#   개발자 PC 에서 영원히 재현되지 않는다. 여기서 cp949 를 강제해 그 PC 를 흉내낸다.
#
#   경로 구분자도 같은 계열이다. os.path.relpath 가 Windows 에서 `a\b` 를 돌려주는데,
#   그 값이 gdrive-manifest.tsv 의 **키**라 mac 이 만든 `a/b` 와 어긋나 중복 제거가 깨진다.
#
# 실행:  bash tests/test_locale_encoding.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AX="$ROOT/plugin/ax/scripts"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

PY="$(command -v python3 || command -v python)"
[ -n "$PY" ] || { echo "✗ python 없음" >&2; exit 1; }

pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1))
        else echo "  ✗ $1 — 기대=$2 실제=$3"; fail=$((fail+1)); fi; }

# 적대적 로케일 — 한국어 Windows 를 흉내낸다. 이 값이 걷히지 않으면 print() 가 cp949 로 쓴다.
# 실제 사고와 같은 조건: errors=replace. strict 면 UnicodeEncodeError 로 죽어 "조용히 깨지는"
# 상황이 재현되지 않는다 — 사고 당시 Slack 에 남은 것은 예외가 아니라 물음표였다.
HOSTILE="cp949:replace"
SAMPLE="동기화 완료 (성공 3 / 스킵 2) ✓"

echo "[1] config.sh 가 로케일을 덮어쓰는가 (근본 수정 A)"

# config.sh 만 source 한 뒤 python 을 돌린다 — 실제 스크립트들이 겪는 것과 같은 조건.
EFF="$(PYTHONIOENCODING="$HOSTILE" bash -c "
  . '$AX/lib/config.sh' >/dev/null 2>&1
  \"\$PS_PY\" -c 'import sys;print(sys.stdout.encoding)'
" 2>/dev/null | tr -d '\r' | tr 'A-Z' 'a-z' | sed 's/[-_]//g')"
chk "적대적 PYTHONIOENCODING=$HOSTILE 가 utf-8 로 덮인다" "utf8" "$EFF"

# 덮이지 않았다면 어떻게 깨지는지 — 이 테스트가 무엇을 막는지 스스로 증명한다.
BROKEN="$(PYTHONIOENCODING="$HOSTILE" "$PY" -c "print('$SAMPLE')" 2>/dev/null \
  | "$PY" -c 'import sys;print(sys.stdin.buffer.read().decode("utf-8","replace").replace(chr(0xFFFD),"?").strip())' 2>/dev/null)"
if [ "$BROKEN" = "$SAMPLE" ]; then
  echo "  ✗ 적대적 로케일 재현 실패 — 이 PC 의 python 이 PYTHONIOENCODING 을 무시한다(테스트 무효)"
  fail=$((fail+1))
else
  echo "  ✓ 적대적 로케일에서는 실제로 깨진다(대조군): ${BROKEN:0:24}…"
  pass=$((pass+1))
fi

# config.sh 를 거치면 같은 문자열이 온전히 나와야 한다.
FIXED="$(PYTHONIOENCODING="$HOSTILE" bash -c "
  . '$AX/lib/config.sh' >/dev/null 2>&1
  \"\$PS_PY\" -c \"print('$SAMPLE')\"
" 2>/dev/null | tr -d '\r')"
chk "config.sh 경유 시 한글·기호가 온전하다" "$SAMPLE" "$FIXED"

echo "[1-b] config 값이 바이트 그대로 나오는가 (ps_cfg_get)"

# 여기서 나온 값이 채널ID·경로·사업명이 되어 모든 후속 단계로 흘러간다.
# 한글이 깨지거나 \r 이 붙으면 비교·URL·경로가 조용히 어긋난다.
mkdir -p "$WORK/cfg/.proj-sync"
cat > "$WORK/cfg/.proj-sync/config.json" <<'JSON'
{"version":1,"project":{"id":"t","name":"AX 원스톱바우처"},"slack":{"channel_id":"C0TEST"}}
JSON
RAW="$(cd "$WORK/cfg" && PYTHONIOENCODING="$HOSTILE" bash -c "
  . '$AX/lib/config.sh' >/dev/null 2>&1
  ps_load_config >/dev/null 2>&1
  ps_cfg_get '.project.name' '.slack.channel_id'
" | "$PY" -c 'import sys;b=sys.stdin.buffer.read();print(repr(b))')"
case "$RAW" in
  *'\r'*) echo "  ✗ 출력에 CR 이 섞였다: $RAW"; fail=$((fail+1)) ;;
  *)      echo "  ✓ 출력에 CR 없음"; pass=$((pass+1)) ;;
esac
CFGNAME="$(cd "$WORK/cfg" && PYTHONIOENCODING="$HOSTILE" bash -c "
  . '$AX/lib/config.sh' >/dev/null 2>&1; ps_load_config >/dev/null 2>&1; ps_cfg '.project.name'")"
chk "config 의 한글 사업명이 온전하다" "AX 원스톱바우처" "$CFGNAME"

echo "[2] 전선(wire) 페이로드가 순수 ASCII 인가 (심층 방어 B)"

# chat.postMessage 페이로드를 만드는 블록을 실제 소스에서 뽑아 돌린다.
#   소스를 복사해 두면 원본이 바뀌어도 테스트가 통과해 버린다 — 실제 파일에서 추출한다.
"$PY" - "$AX/lib/slack_api.sh" > "$WORK/payload.py" <<'PY'
import re,sys
s=open(sys.argv[1],encoding="utf-8").read()
m=re.search(r"ps_slack_post_message\(\).*?<<'PY'\n(.*?)\nPY\n", s, re.S)
if not m:
    sys.stderr.write("ps_slack_post_message 의 python 블록을 찾지 못했다\n"); raise SystemExit(1)
sys.stdout.write(m.group(1))
PY
[ -s "$WORK/payload.py" ] || { echo "  ✗ 페이로드 블록 추출 실패" >&2; exit 1; }

PAYLOAD="$(PYTHONIOENCODING="$HOSTILE" "$PY" "$WORK/payload.py" C0TEST "$SAMPLE" "" 2>/dev/null)"
IS_ASCII="$(printf '%s' "$PAYLOAD" | LC_ALL=C grep -qP '[^\x00-\x7F]' 2>/dev/null && echo no || echo yes)"
chk "페이로드에 non-ASCII 바이트가 없다" "yes" "$IS_ASCII"

# ASCII 라도 내용이 보존돼야 의미가 있다 — 디코딩해서 원문과 대조한다.
ROUNDTRIP="$(printf '%s' "$PAYLOAD" | "$PY" -c 'import json,sys;print(json.load(sys.stdin)["text"])' 2>/dev/null)"
chk "디코딩하면 원문과 같다" "$SAMPLE" "$ROUNDTRIP"

echo "[3] 저장소에 남는 경로가 POSIX 인가 (수정 C)"

# Windows 를 흉내내 ntpath 로 relpath 를 만든 뒤, slack_download.sh 가 쓰는 정규화를 건다.
NORM="$("$PY" - <<'PY'
import ntpath, posixpath
# Windows 에서 os.path 는 ntpath 다 — os.sep 은 '\\'
dst  = ntpath.join("slack-files", "01_제안요청서_RFP", "F0X__사업계획서.hwp")
rel  = ntpath.relpath(dst, ".")
print(rel.replace("\\", "/"))
PY
)"
chk "역슬래시 경로가 POSIX 로 정규화된다" "slack-files/01_제안요청서_RFP/F0X__사업계획서.hwp" "$NORM"

# 소스 불변식 — relpath 를 쓰는 줄이 정규화 없이 추가되면 여기서 걸린다.
BARE="$(grep -n 'os\.path\.relpath(' "$AX/slack_download.sh" | grep -vc 'replace(os\.sep' || true)"
chk "slack_download.sh 의 relpath 가 전부 정규화를 거친다" "0" "$BARE"

echo "[4] 새 발신 지점이 방어를 건너뛰지 않는가 (회귀 가드)"

# curl --data-binary 로 나가는 페이로드를 만드는 print(json.dumps(...)) 는 전부 ensure_ascii=True 여야 한다.
LEAK=0
for f in "$AX/lib/slack_api.sh" "$AX/slack_upload.sh" "$AX/notion_plan.sh"; do
  n="$(grep -c 'print(json\.dumps(.*ensure_ascii=False' "$f" 2>/dev/null || true)"
  [ "${n:-0}" -gt 0 ] && { echo "     ↳ $(basename "$f"): $n 건"; LEAK=$((LEAK+n)); }
done
chk "발신 페이로드에 ensure_ascii=False 가 남아 있지 않다" "0" "$LEAK"

# stdout 으로 JSON 을 내보내는 md_to_notion 은 크기 산정 때문에 ensure_ascii=False 를 유지한다.
# 대신 바이트를 직접 써야 한다 — print()/json.dump(sys.stdout) 로 되돌아가면 다시 깨진다.
SAFE="$(grep -c 'sys\.stdout\.buffer\.write' "$AX/lib/md_to_notion.py" 2>/dev/null || true)"
chk "md_to_notion 이 stdout 에 바이트를 직접 쓴다" "1" "$SAFE"

echo "------------------------------------"
echo "결과: ✓ $pass / ✗ $fail"
[ "$fail" -eq 0 ]
