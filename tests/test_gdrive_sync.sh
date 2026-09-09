#!/usr/bin/env bash
# 회귀 테스트 — gdrive_sync.sh (v1.19.0, NAS 대체)
#
# 왜 있는가:
#   NAS 판은 사내망·실물 장비가 있어야 검증됐고, 그래서 E2E 실측이 1회성 기록으로만 남았다.
#   Drive 판은 rclone 을 스텁으로 갈아끼워 **네트워크·계정 없이** 계약을 고정한다.
#   특히 지키려는 것은 E-code 다 — run-sync 가 이 값으로 스킵·보고를 분기하므로,
#   숫자가 바뀌면 동기화 전체의 실패 처리가 조용히 어긋난다.
#
# 실행:  bash tests/test_gdrive_sync.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$ROOT/plugin/ax/scripts/gdrive_sync.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
[ -f "$TARGET" ] || { echo "✗ 대상 없음: $TARGET" >&2; exit 1; }

PYBIN="$(command -v python3 || command -v python)"
pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; pass=$((pass+1))
        else echo "  ✗ $1 — 기대=$2 실제=$3"; fail=$((fail+1)); fi; }

# ── 가짜 사업 폴더 ────────────────────────────────────────────
PROJ="$WORK/proj"; mkdir -p "$PROJ/.proj-sync" "$PROJ/slack-files/10_착수"
cat > "$PROJ/.proj-sync/config.json" <<'J'
{"project":{"id":"demo"},
 "categories":[{"key":"10_착수"}],
 "gdrive":{"enabled":true,"remote":"gdrive","team_folder":"TEAM",
           "base_path":"{team_folder}/{project_id}","upload_exts":["pdf"]}}
J
printf 'hello\n' > "$PROJ/slack-files/10_착수/a.pdf"

BIN="$WORK/bin"; mkdir -p "$BIN"
export RC_LOG="$WORK/rclone.log"   # 스텁은 별도 프로세스다 — export 해야 보인다
STUB="$BIN/rclone"

# ⚠ **PATH 로 격리하지 않는다.** lib/config.sh 가 PATH 맨 앞에 /opt/homebrew/bin 을 넣으므로
#   PATH 를 좁혀도 실제 rclone 이 이긴다. 실제로 이 테스트를 처음 돌렸을 때 **운영 Drive 에
#   테스트 파일이 올라갔다.** 그래서 스크립트에 PS_RCLONE_BIN 주입 지점을 두고 여기서 그것만 쓴다.

# rclone 스텁 — RC_MODE 로 시나리오를 고른다.
make_rclone() {
  cat > "$STUB" <<'STUB'
#!/usr/bin/env bash
# 안전장치 — 스텁이 실제 원격을 건드릴 수 없음을 스스로 증명한다.
[ -n "${RC_LOG:-}" ] || { echo "stub: RC_LOG 미설정 — 실행 거부" >&2; exit 99; }
echo "$*" >> "$RC_LOG"
case "$1" in
  listremotes) [ "${RC_NOREMOTE:-}" = "1" ] || echo "gdrive:" ;;
  about)       [ "${RC_POLICY:-}" = "1" ] && { echo "Failed to about: Error 400: admin_policy_enforced" >&2; exit 1; }
               [ "${RC_NOAUTH:-}" = "1" ] && exit 1; echo "Total: 1" ;;
  config)      # `config create …` — rclone 은 결과 config(token 포함)를 stdout 에 낸다. 스크립트가 버려야 한다.
               [ "${RC_CREATEFAIL:-}" = "1" ] && { echo "${RC_CREATE_ERR:-oauth2: cannot fetch token}" >&2; exit 1; }
               echo "[gdrive]"; echo "token = {\"access_token\":\"STUB-SHOULD-NOT-LEAK\"}"; exit 0 ;;
  version)     echo "rclone v9.9.9-stub" ;;
  lsjson)      printf '%s\n' "${RC_LSJSON:-[]}" ;;
  deletefile) [ "${RC_DELFAIL:-}" = "1" ] && exit 1; exit 0 ;;
  copy)       [ "${RC_COPYFAIL:-}" = "1" ] && exit 1
              # pull 은 rclone 로그에서 전송 건수를 얻는다. 파싱 불가 로그도 흉내 낼 수 있어야 한다.
              printf '%s\n' "${RC_PULL_LOG-{\"level\":\"info\",\"msg\":\"Copied (new)\",\"object\":\"a.pdf\"}}"; exit 0 ;;
  copyto|mkdir|moveto) [ "${RC_COPYFAIL:-}" = "1" ] && exit 1; exit 0 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$STUB"
}
make_rclone

run() { : > "$RC_LOG"
        (cd "$PROJ" && PS_RCLONE_BIN="$STUB" PS_GDRIVE_PROMPT_TIMEOUT=1 \
           bash "$TARGET" "$@" > "$WORK/out" 2> "$WORK/err"); echo $?; }
# rclone 자체가 없는 상황 — 존재하지 않는 경로를 가리킨다(PATH 를 건드리지 않는다).
run_norclone() { : > "$RC_LOG"
        (cd "$PROJ" && PS_RCLONE_BIN="$WORK/no-such-rclone" \
           bash "$TARGET" "$@" > "$WORK/out" 2> "$WORK/err"); echo $?; }

# 로컬 a.pdf 의 md5 — 「해시 같으면 스킵」 검증용
LMD5="$(md5 -q "$PROJ/slack-files/10_착수/a.pdf" 2>/dev/null || md5sum "$PROJ/slack-files/10_착수/a.pdf" | cut -d' ' -f1)"

echo "── E-code: run-sync 가 이 값으로 분기한다"
chk "E10 rclone 미설치"      "10" "$(run_norclone push)"
chk "  사유 출력"            "1"  "$(grep -c 'E10' "$WORK/err")"
chk "E13 remote 미설정"      "13" "$(: > "$RC_LOG"; (cd "$PROJ" && PS_RCLONE_BIN="$STUB" RC_NOREMOTE=1 bash "$TARGET" push >"$WORK/out" 2>"$WORK/err" </dev/null); echo $?)"
chk "E11 인증 불가"          "11" "$(: > "$RC_LOG"; (cd "$PROJ" && PS_RCLONE_BIN="$STUB" RC_NOAUTH=1 bash "$TARGET" push >"$WORK/out" 2>"$WORK/err" </dev/null); echo $?)"

echo "── push: 해시가 같으면 올리지 않는다 (멱등)"
export RC_LSJSON="[{\"Path\":\"10_착수/a.pdf\",\"Size\":6,\"ModTime\":\"2020-01-01T00:00:00Z\",\"Hashes\":{\"md5\":\"$LMD5\"}}]"
chk "종료코드 0"             "0" "$(run push)"
chk "스킵 안내"              "1" "$(grep -c '해시 일치' "$WORK/out")"
chk "copyto 호출 0회"        "0" "$(grep -c '^copyto' "$RC_LOG" || true)"

echo "── push: 내용이 다르면 올린다"
export RC_LSJSON='[{"Path":"10_착수/a.pdf","Size":9,"ModTime":"2020-01-01T00:00:00Z","Hashes":{"md5":"deadbeef"}}]'
chk "종료코드 0"             "0" "$(run push)"
chk "copyto 1회"             "1" "$(grep -c '^copyto' "$RC_LOG" || true)"
chk "완료 보고"              "1" "$(grep -c 'push 완료 (1 파일)' "$WORK/out")"
SEEN_STUB="$([ -s "$RC_LOG" ] && echo yes || echo no)"   # 스텁이 실제로 호출됐다는 증거

echo "── push 충돌: 원격이 더 최신이면 헤드리스에서 E16"
export RC_LSJSON='[{"Path":"10_착수/a.pdf","Size":9,"ModTime":"2099-01-01T00:00:00Z","Hashes":{"md5":"deadbeef"}}]'
rc="$(run push < /dev/null)"
chk "E16"                    "16" "$rc"
chk "충돌 목록 보고"          "1"  "$(grep -c '충돌 가능' "$WORK/err")"
chk "아무것도 안 올림"        "0"  "$(grep -c '^copyto' "$RC_LOG" || true)"

echo "── 충돌 승인: PS_GDRIVE_YES=1 이면 백업 후 덮어쓴다"
rc="$(: > "$RC_LOG"; (cd "$PROJ" && PS_RCLONE_BIN="$STUB" PS_GDRIVE_PROMPT_TIMEOUT=1 PS_GDRIVE_YES=1 bash "$TARGET" push >"$WORK/out" 2>"$WORK/err" </dev/null); echo $?)"
chk "종료코드 0"             "0" "$rc"
chk "덮어쓰기 전 백업(moveto)" "1" "$(grep -c '^moveto.*\.bak-' "$RC_LOG" || true)"
chk "그 다음 업로드"          "1" "$(grep -c '^copyto' "$RC_LOG" || true)"

echo "── 업로드 실패는 E14 로 드러난다 (조용히 성공 보고 금지)"
export RC_LSJSON='[]'
rc="$(: > "$RC_LOG"; (cd "$PROJ" && PS_RCLONE_BIN="$STUB" PS_GDRIVE_PROMPT_TIMEOUT=1 RC_COPYFAIL=1 bash "$TARGET" push >"$WORK/out" 2>"$WORK/err" </dev/null); echo $?)"
chk "E14"                    "14" "$rc"
chk "실패 파일명 보고"        "1"  "$(grep -c '업로드 실패' "$WORK/err")"

echo "── NFD/NFC: macOS 한글 경로가 매번 재업로드되지 않는가 (issue #21·#22 와 같은 결함)"
# 로컬(macOS)은 NFD, Drive 에 저장된 경로는 NFC — 맞추지 않으면 해시 조회가 빗나가
# 전건이 「변경됨」으로 보여 매번 다시 올라가고, Drive 에 두 경로가 쌓인다.
NFC_REL="$("$PYBIN" -c 'import sys,unicodedata;sys.stdout.write(unicodedata.normalize("NFC","10_착수/a.pdf"))')"
export RC_LSJSON="[{\"Path\":\"$NFC_REL\",\"Size\":6,\"ModTime\":\"2020-01-01T00:00:00Z\",\"Hashes\":{\"md5\":\"$LMD5\"}}]"
chk "종료코드 0"             "0" "$(run push)"
chk "NFC 원격 ↔ 로컬 경로가 같은 키로 대조" "1" "$(grep -c '해시 일치' "$WORK/out")"
chk "재업로드 없음(copyto 0회)" "0" "$(grep -c '^copyto' "$RC_LOG" || true)"

echo "── pull: --include 패턴이 CWD 글로빙에 오염되지 않는가 (리뷰 High)"
# ⚠ `--include *.pdf` 를 따옴표 없이 넘기면 셸이 **실행 디렉터리에 대해** 글로빙한다.
#   사업 루트에 pdf 가 하나만 있어도 그 이름만 받고 나머지는 전부 건너뛴 채 「✓ 완료」를 보고한다.
#   조용히 대부분을 안 받는 형태라 사람이 알아채지 못한다.
touch "$PROJ/제안서_최종.pdf"                 # 사업 루트에 pdf 1개 — 흔한 상황
rc="$(run pull)"
chk "종료코드 0"                    "0" "$rc"
chk "include 패턴이 리터럴로 전달"   "1" "$(grep -c -- '--include \*\.pdf' "$RC_LOG" || true)"
chk "CWD 파일명이 새어들지 않음"     "0" "$(grep -c '제안서_최종.pdf' "$RC_LOG" || true)"
touch "$PROJ/붙임1.pdf" "$PROJ/붙임2.pdf"     # 여러 개 — rclone 인자 초과로 이어지던 경우
rc="$(run pull)"
chk "여러 개여도 종료코드 0"         "0" "$rc"
chk "여전히 리터럴"                  "1" "$(grep -c -- '--include \*\.pdf' "$RC_LOG" || true)"
rm -f "$PROJ"/*.pdf

echo "── pull: 건수를 못 읽으면 0 이라고 말하지 않는다 (리뷰 Medium)"
# rclone 로그 문구를 파싱해 세면, 문구가 바뀐 날 「0 파일」이라는 **틀린 수치**를 보고하게 된다.
# 셀 수 없으면 세지 못했다고 말해야 한다.
export RC_PULL_LOG="__UNPARSEABLE__"
rc="$(run pull)"
chk "종료코드 0"                    "0" "$rc"
chk "0 파일 이라고 말하지 않음"      "0" "$(grep -c '0 파일' "$WORK/out" || true)"
chk "건수 미상을 밝힘"               "1" "$(grep -c '건수 미상' "$WORK/out" || true)"
unset RC_PULL_LOG

echo "── doctor: 프로브 정리 실패를 삼키지 않는가 (리뷰 Low)"
rc="$(: > "$RC_LOG"; (cd "$PROJ" && PS_RCLONE_BIN="$STUB" RC_DELFAIL=1 bash "$TARGET" doctor >"$WORK/out" 2>"$WORK/err" </dev/null); echo $?)"
chk "종료코드 0(치명 아님)"          "0" "$rc"
chk "잔존 파일을 알림"               "1" "$(grep -c 'proj-sync-probe' "$WORK/err" || true)"

echo "── status·init 도 최소 동작을 지킨다"
chk "status 종료코드 0"              "0" "$(run status)"
chk "status 가 remote·base 표시"     "1" "$(grep -c 'remote=gdrive' "$WORK/out" || true)"
chk "init 종료코드 0"                "0" "$(run init)"
chk "init 이 카테고리 폴더 생성"      "1" "$(grep -c '^mkdir .*10_' "$RC_LOG" || true)"

echo "── 비활성 사업은 조용히 통과 (동기화를 막지 않는다)"
python3 - "$PROJ/.proj-sync/config.json" <<'PY'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); c["gdrive"]["enabled"]=False
json.dump(c, open(p,"w"), ensure_ascii=False)
PY
chk "종료코드 0"             "0" "$(run push)"
chk "비활성 안내"            "1" "$(grep -c 'enabled=false' "$WORK/out")"

echo "── setup-remote: 본인 Google 계정 개인 OAuth 로 remote 를 만든다 (v1.21.0 단일 경로)"
python3 - "$PROJ/.proj-sync/config.json" <<'PY2'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); c["gdrive"]["enabled"]=True; c["gdrive"]["team_drive_id"]="0TDRIVEID"
json.dump(c, open(p,"w"), ensure_ascii=False)
PY2
export PS_SECRETS_REPO="ax-harness/__no_such_repo_for_test__"    # 실 secrets repo 로 나가지 않는다
chk "setup-remote → exit 0"                        "0" "$(run setup-remote)"
chk "config create 를 기본 client 로 호출(client_id 없음)" "1" "$(grep -c '^config create gdrive drive scope=drive team_drive=0TDRIVEID' "$RC_LOG" || true)"
chk "client_id 인자를 쓰지 않음"                    "0" "$(grep -c 'client_id=' "$RC_LOG" || true)"
chk "생성 후 about 로 검증"                        "1" "$(grep -c '^about gdrive:' "$RC_LOG" || true)"
chk "rclone 이 낸 token 이 stdout 에 없음"           "0" "$(grep -c 'STUB-SHOULD-NOT-LEAK' "$WORK/out" || true)"
chk "준비됨 안내"                                   "1" "$(grep -c '준비됨' "$WORK/out" || true)"
# team_drive_id 없는 config 에서는 extras 없이 만든다
python3 - "$PROJ/.proj-sync/config.json" <<'PY2'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); c["gdrive"]["team_drive_id"]=""; json.dump(c, open(p,"w"), ensure_ascii=False)
PY2
chk "team_drive_id 없음 → extras 없이 create"       "0" "$(: > "$RC_LOG"; (cd "$PROJ" && PS_RCLONE_BIN="$STUB" bash "$TARGET" setup-remote >"$WORK/out" 2>"$WORK/err" </dev/null); grep -c 'team_drive=' "$RC_LOG" || true)"
python3 - "$PROJ/.proj-sync/config.json" <<'PY2'
import json,sys
p=sys.argv[1]; c=json.load(open(p)); c["gdrive"]["team_drive_id"]="0TDRIVEID"; json.dump(c, open(p,"w"), ensure_ascii=False)
PY2
chk "config create 가 정책 차단으로 실패 → E12"      "12" "$(: > "$RC_LOG"; (cd "$PROJ" && PS_RCLONE_BIN="$STUB" RC_CREATEFAIL=1 RC_CREATE_ERR='Error 400: admin_policy_enforced' bash "$TARGET" setup-remote >"$WORK/out" 2>"$WORK/err" </dev/null); echo $?)"
chk "  관리자에게 허용 요청 안내"                    "1" "$(grep -c '관리자' "$WORK/err" || true)"
chk "config create 가 그 외 사유로 실패 → E11"       "11" "$(: > "$RC_LOG"; (cd "$PROJ" && PS_RCLONE_BIN="$STUB" RC_CREATEFAIL=1 bash "$TARGET" setup-remote >"$WORK/out" 2>"$WORK/err" </dev/null); echo $?)"

echo "── E12: 기존 remote 가 조직 정책으로 차단되면 재인증이 아니라 관리자 허용 요청으로 안내"
chk "push → E12"                                   "12" "$(: > "$RC_LOG"; (cd "$PROJ" && PS_RCLONE_BIN="$STUB" RC_POLICY=1 bash "$TARGET" push >"$WORK/out" 2>"$WORK/err" </dev/null); echo $?)"
chk "  관리자 허용 요청 안내"                        "1"  "$(grep -c '관리자에게 rclone 허용' "$WORK/err" || true)"
chk "  E11 재인증 안내는 없음"                       "0"  "$(grep -c 'E11' "$WORK/err" || true)"
unset PS_SECRETS_REPO

echo "── 안전: 테스트가 실제 remote 를 건드리지 않았는가"
# 스텁은 호출을 전부 RC_LOG 에 남긴다. 실제 rclone 이 끼어들었다면 로그와 동작이 어긋난다.
chk "스텁이 실행됨(로그 존재)" "yes" "${SEEN_STUB:-no}"
chk "스크립트가 PS_RCLONE_BIN 을 존중" "1" \
  "$(grep -c 'RCLONE="\${PS_RCLONE_BIN:-rclone}"' "$TARGET" || true)"
chk "직접 rclone 호출 없음" "0" \
  "$(grep -cE '(^|[^\"$])rclone (listremotes|about|version|lsjson|copyto|copy|mkdir|deletefile|moveto)' "$TARGET" || true)"

echo
echo "결과 — 통과 $pass · 실패 $fail"
[ "$fail" -eq 0 ]
