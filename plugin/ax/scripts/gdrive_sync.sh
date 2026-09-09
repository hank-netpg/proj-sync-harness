#!/usr/bin/env bash
# proj-sync: Google Drive 동기화 (대용량 사무파일 저장소) — rclone 기반
#
#   NAS(Synology File Station)를 대체한다. 담당은 같다 — **텍스트가 아닌 사무파일**
#   (hwp·doc·ppt·xls·pdf·zip 등). 텍스트 SSOT 는 여전히 GitHub 다.
#
# 왜 rclone 인가
#   claude.ai Google Drive 커넥터에는 **로컬 경로 업로드가 없다.** 파일 바이트가 도구 호출 인자
#   (base64) 안에 있어야 하므로 파일이 에이전트 컨텍스트를 **두 번**(스크립트 출력 → 도구 인자)
#   통과한다 — 64KiB 가 약 70k 토큰, 1MiB 는 약 1.1M 토큰이라 창에 들어가지 않는다(v1.21.0 설계 실측).
#   대용량이 정확히 이 저장소의 존재 이유이므로 커넥터만으로는 대체가 성립하지 않는다.
#   rclone 은 크기 제한이 없고, 부수효과가 **스크립트 엔트리포인트**에 남아 A3 원칙을 지키며,
#   스케줄러·헤드리스(`claude -p`)에서도 동작한다. 커넥터는 조회·공유 링크 같은 보조에 쓴다.
#
# 자격증명은 **사용자 본인의 Google 계정**이다 (팀 토큰 아님 — v1.21.0 개인 OAuth 단일화)
#   `setup-remote` 가 rclone 기본 client 로 remote 를 만든다(머신당 1회 · 브라우저 인증).
#   rclone 기본 client 는 서드파티 앱이라 Workspace 관리자가 막을 수 있다 — 그 경우 E12 로 감지해
#   관리자에게 rclone 허용을 요청하도록 안내한다(코드로 우회하지 않는다).
#   근거: rclone 공식 docs (https://rclone.org/drive/), Google Workspace Admin Help
#         "Control which third-party & internal apps access Google Workspace data".
#
# 멱등성
#   rclone 이 체크섬(md5)으로 동일 파일을 건너뛴다. NAS 판의 sha256 매니페스트와 같은 목적이며,
#   원격의 실제 해시를 쓰므로 매니페스트가 어긋날 여지가 없다.
#
# 사용:
#   gdrive_sync.sh init | push | pull | status | doctor [--quick] | setup-remote
#   gdrive_sync.sh push-file <로컬파일> <Drive상대경로>
#     ↳ **config 를 읽지 않는 애드혹 경로다.** gdrive.enabled·base_path 를 우회하고
#       경로를 remote 루트 기준으로 그대로 쓴다. 사업 동기화가 아니라 단발 전송용.
#
# 종료코드(E-code) — run-sync 가 이 값으로 분기한다:
#   0 성공/비활성 · 10 rclone 미설치 · 11 remote 도달·인증 불가 · 12 관리자 정책 차단(서드파티 앱)
#   13 remote 미설정 · 14 쓰기 권한 실패 · 15 (결번 — v1.21.0 에서 팀 자격증명 경로 삭제) · 16 push 충돌 미해결
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
set +e

CMD="${1:-status}"; shift 2>/dev/null || true

# 임시파일은 중단(Ctrl-C·kill)에도 남지 않게 한다. 목록에 추가한 뒤 만든다.
PS_GD_TMP=""
gd_tmp() { local t; t="$(mktemp)"; PS_GD_TMP="$PS_GD_TMP $t"; echo "$t"; }
gd_cleanup() { [ -n "$PS_GD_TMP" ] && rm -f $PS_GD_TMP 2>/dev/null; return 0; }
trap gd_cleanup EXIT INT TERM

fmtime() { stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null; }

# 실행할 rclone 바이너리. PATH 에 의존하지 않고 **명시적으로** 고른다.
#   · lib/config.sh 가 PATH 맨 앞에 /opt/homebrew/bin 을 넣으므로, PATH 를 좁혀 격리하려는
#     시도(테스트·샌드박스)가 조용히 무력화된다. 그 상태로 push 를 돌리면 **의도치 않은 실제
#     원격에 파일이 올라간다.** 주입 지점을 코드에 두어 그런 일이 생기지 않게 한다.
#   · 운영에서도 여러 rclone 사본이 깔린 머신에서 어느 것을 쓸지 고정하는 데 쓴다.
RCLONE="${PS_RCLONE_BIN:-rclone}"

have_rclone() {
  command -v "$RCLONE" >/dev/null 2>&1 && return 0
  echo "[gdrive][E10] ✗ rclone 미설치 — 대용량 전송에 필요합니다." >&2
  case "$(uname -s)" in
    Darwin) echo "      설치:  brew install rclone" >&2 ;;
    MINGW*|MSYS*|CYGWIN*) echo "      설치:  https://rclone.org/downloads/ (Windows 64-bit)" >&2 ;;
    *) echo "      설치:  sudo apt install rclone  (또는 https://rclone.org/install.sh)" >&2 ;;
  esac
  return 10
}

# ── 애드혹 단일 파일 전송 (config 불요) ──────────────────────
if [ "$CMD" = "push-file" ]; then
  SRC_FILE="${1:-}"; DEST_REL="${2:-}"
  [ -f "$SRC_FILE" ] || { echo "[gdrive] ✗ 파일 없음: $SRC_FILE" >&2
    echo "  사용: gdrive_sync.sh push-file <로컬파일> <Drive상대경로>" >&2; exit 1; }
  [ -n "$DEST_REL" ] || { echo "[gdrive] ✗ Drive 대상 경로 미지정 (2번째 인자)" >&2; exit 1; }
  have_rclone || exit $?
  REMOTE="${PS_GDRIVE_REMOTE:-gdrive}"
  "$RCLONE" copyto "$SRC_FILE" "$REMOTE:$DEST_REL" 2>&1 \
    || { echo "[gdrive][E14] ✗ 업로드 실패 — remote($REMOTE) 쓰기 권한·경로 확인" >&2; exit 14; }
  echo "[gdrive] ✓ 업로드: $DEST_REL"
  exit 0
fi

ps_load_config || { echo "[gdrive] config.json 로드 실패 (.proj-sync/config.json 필요, 또는 애드혹: gdrive_sync.sh push-file <파일> <경로>)" >&2; exit 1; }

GD_ENABLED="$(ps_cfg '.gdrive.enabled')"
[ "$GD_ENABLED" = "true" ] || {
  echo "[gdrive] config.gdrive.enabled=false — Google Drive 비활성. (활성화: config 에 gdrive.remote·base_path 설정)"
  exit 0; }

REMOTE="$(ps_cfg '.gdrive.remote')"; [ -z "$REMOTE" ] || [ "$REMOTE" = "null" ] && REMOTE="gdrive"
TEAM="$(ps_cfg '.gdrive.team_folder')"; [ "$TEAM" = "null" ] && TEAM=""
PROJ="$(ps_cfg '.project.id')"; [ -z "$PROJ" ] || [ "$PROJ" = "null" ] && PROJ="$(basename "$PS_ROOT")"
BASE_TPL="$(ps_cfg '.gdrive.base_path')"; [ -z "$BASE_TPL" ] || [ "$BASE_TPL" = "null" ] && BASE_TPL="{team_folder}/{project_id}"
BASE="${BASE_TPL//\{team_folder\}/$TEAM}"; BASE="${BASE//\{project_id\}/$PROJ}"
BASE="${BASE#/}"; BASE="${BASE%/}"
[ -n "$BASE" ] || { echo "[gdrive][E13] ✗ base_path 가 비었습니다 — config.gdrive.base_path·team_folder 확인" >&2; exit 13; }

RD="$REMOTE:$BASE"
SRC="$PS_ROOT/slack-files"
exts="$(ps_cfg '.gdrive.upload_exts' | "$PS_PY" -c "import json,sys;print(' '.join(json.load(sys.stdin)))" 2>/dev/null)"
[ -n "$exts" ] || exts="hwp hwpx doc docx ppt pptx xls xlsx pdf png jpg jpeg gif zip"

cat_keys() { ps_cfg '.categories' | "$PS_PY" -c "import json,sys; print('\n'.join(c['key'] for c in json.load(sys.stdin)))" 2>/dev/null; }

# remote 도달·인증 확인. rclone 은 미설정 remote 를 「directory not found」로 답하므로 구분해 안내한다.
remote_ok() {
  have_rclone || return $?
  if ! "$RCLONE" listremotes 2>/dev/null | grep -qx "$REMOTE:"; then
    echo "[gdrive][E13] ✗ rclone remote '$REMOTE' 미설정" >&2
    echo "      설정(머신당 1회):  bash \"$HERE/gdrive_sync.sh\" setup-remote" >&2
    echo "      (본인 Google 계정 브라우저 인증 1회로 remote 를 만든다)" >&2
    return 13
  fi
  local aerr; aerr="$(gd_tmp)"
  if ! "$RCLONE" about "$REMOTE:" >/dev/null 2>"$aerr"; then
    # 관리자 정책 차단 — Google OAuth 가 admin_policy_enforced / access_denied 로 거절한다.
    #   회사 계정 팀원이 rclone 기본 client(서드파티 앱)로 인증했을 때 나는 형태다. 재인증으로는
    #   풀리지 않으므로 다른 안내가 필요하다. (문자열은 파일럿에서 확정 — 검증 필요)
    if grep -qiE 'admin_policy_enforced|access_denied|policy_enforced|blocked by (your )?(admin|organization)' "$aerr"; then
      echo "[gdrive][E12] ✗ remote '$REMOTE' 가 조직 정책으로 차단됨 — Workspace 관리자가 서드파티 앱(rclone)을 막았습니다" >&2
      echo "      Workspace 관리자에게 rclone 허용(관리 콘솔 → 앱 접근 통제)을 요청하세요 — 재인증으로는 풀리지 않습니다." >&2
      echo "      계정을 바꿔 다시 만들려면:  rclone config delete $REMOTE  →  bash \"$HERE/gdrive_sync.sh\" setup-remote" >&2
      return 12
    fi
    echo "[gdrive][E11] ✗ remote '$REMOTE' 도달·인증 불가 — 네트워크 또는 토큰 만료" >&2
    echo "      재인증:  rclone config reconnect $REMOTE:" >&2
    return 11
  fi
  return 0
}

# ── remote 자동 생성 ─────────────────────────────────────────
# `rclone config create` 를 비대화식으로 호출한다 — 개인 OAuth 단일 경로(v1.21.0).
#   rclone 이 생성 결과로 config 전체(token 포함)를 stdout 에 내므로 그 출력은 버린다.
#   stderr 는 브라우저가 안 열릴 때 사용자가 인증 URL 을 봐야 하므로 그대로 둔다.
gd_setup_remote() {
  have_rclone || return $?
  local td rf extra="" rc cerr
  td="$(ps_cfg '.gdrive.team_drive_id')"; [ "$td" = "null" ] && td=""
  rf="$(ps_cfg '.gdrive.root_folder_id')"; [ "$rf" = "null" ] && rf=""
  [ -n "$td" ] && extra="$extra team_drive=$td"
  [ -n "$rf" ] && extra="$extra root_folder_id=$rf"
  cerr="$(gd_tmp)"
  echo "[gdrive] remote '$REMOTE' 생성 — 본인 Google 계정으로 브라우저 인증 창이 열립니다 (머신당 1회)"
  # shellcheck disable=SC2086
  "$RCLONE" config create "$REMOTE" drive scope=drive $extra >/dev/null 2>"$cerr"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    if grep -qiE 'admin_policy_enforced|access_denied|policy_enforced' "$cerr"; then
      echo "[gdrive][E12] ✗ 조직 정책이 rclone(서드파티 앱)을 차단했습니다." >&2
      echo "      Workspace 관리자에게 rclone 허용(관리 콘솔 → 앱 접근 통제)을 요청하세요." >&2
      echo "      개인 Google 계정을 쓸 수 있으면 그 계정으로 다시 인증해도 됩니다." >&2
      return 12
    fi
    echo "[gdrive][E11] ✗ remote 생성 실패 — $(grep -v -i 'secret\|token' "$cerr" | tail -3 | tr '\n' ' ')" >&2
    return 11
  fi
  remote_ok || return $?
  echo "[gdrive] ✓ remote '$REMOTE' 준비됨 (본인 Google 계정${td:+ · 공유 드라이브 $td})"
  return 0
}

# 원격 파일 목록 → "상대경로 \t md5 \t mtime(epoch)" (없으면 빈 출력)
remote_index() {
  # ⚠ `cmd | python - <<'PY'` 로 쓰면 **heredoc 이 파이프를 덮어써** 파이썬이 stdin 에서
  #   프로그램만 읽고 데이터는 받지 못한다 → 원격 인덱스가 **조용히 항상 비고**, 전건이
  #   「변경됨」으로 보여 매번 다시 올라가며 충돌 탐지도 죽는다. 프로그램은 -c 로 넘기고
  #   stdin 은 파이프 전용으로 남긴다.
  "$RCLONE" lsjson -R --files-only --hash "$RD" 2>/dev/null | "$PS_PY" -c '
import json, sys, calendar, time, unicodedata
try: rows = json.load(sys.stdin)
except Exception: rows = []
for r in rows:
    h = (r.get("Hashes") or {}).get("md5") or ""
    t = r.get("ModTime") or ""
    ep = ""
    if t:
        base = t.split(".")[0].replace("Z", "")
        try: ep = str(calendar.timegm(time.strptime(base, "%Y-%m-%dT%H:%M:%S")))
        except Exception: ep = ""
    # 원격 경로도 NFC 로 맞춘다 — 로컬 목록과 같은 형태여야 대조가 성립한다.
    print("\t".join([unicodedata.normalize("NFC", r.get("Path", "")), h, ep]))
'
}

local_md5() { md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

case "$CMD" in
  status)
    echo "[gdrive] remote=$REMOTE  base=$BASE"
    echo "[gdrive] 로컬 원본: $SRC"
    if remote_ok; then
      n="$(remote_index | grep -c . 2>/dev/null || true)"
      echo "[gdrive] 원격 파일 ${n:-0}건"
    fi
    ;;

  doctor)
    QUICK="${1:-}"
    echo "=== gdrive doctor ==="
    remote_ok || exit $?
    echo "  ✓ rclone: $("$RCLONE" version 2>/dev/null | head -1)"
    echo "  ✓ remote '$REMOTE' 인증됨"
    if [ "$QUICK" != "--quick" ]; then
      PROBE="$(gd_tmp)"; echo "proj-sync write probe" > "$PROBE"
      if "$RCLONE" copyto "$PROBE" "$RD/.proj-sync-probe" >/dev/null 2>&1; then
        # 정리 실패를 삼키면 Drive 에 프로브 파일이 남는데 아무도 모른다.
        # 쓰기 자체는 성공했으므로 ✓ 는 유지하되, 남은 것은 반드시 알린다.
        if ! "$RCLONE" deletefile "$RD/.proj-sync-probe" >/dev/null 2>&1; then
          echo "  ⚠ 프로브 파일 정리 실패 — Drive 에 $BASE/.proj-sync-probe 가 남았습니다(수동 삭제 필요)" >&2
        fi
        echo "  ✓ 쓰기 권한 OK ($BASE)"
      else
        echo "  ✗ [E14] 쓰기 프로브 실패 — '$BASE' 쓰기 권한 확인" >&2; rm -f "$PROBE"; exit 14
      fi
      rm -f "$PROBE"
    fi
    echo "[gdrive doctor] ✓ 통과"
    ;;

  init)
    remote_ok || exit $?
    n=0
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      "$RCLONE" mkdir "$RD/$k" >/dev/null 2>&1 && n=$((n+1))
    done < <(cat_keys)
    echo "[gdrive] ✓ 사업 폴더 생성: $BASE ($n 카테고리)"
    ;;

  push)
    remote_ok || exit $?
    [ -d "$SRC" ] || { echo "[gdrive] 원본 폴더 없음: $SRC — 전송할 것이 없습니다"; exit 0; }

    RIDX="$(gd_tmp)"; remote_index > "$RIDX"
    # ⚠ `awk -v k=…` 는 값 안의 백슬래시를 **이스케이프로 해석**한다 — 파일명에 `\` 가 있으면
    #   키가 어긋나 항상 「원격에 없음」이 되어 매번 다시 올라간다(NFD 결함과 같은 계열).
    #   ENVIRON 으로 넘기면 해석 없이 그대로 전달된다.
    rmd5() { NP_K="$1" awk -F'\t' '$1==ENVIRON["NP_K"]{print $2; exit}' "$RIDX"; }
    rmt()  { NP_K="$1" awk -F'\t' '$1==ENVIRON["NP_K"]{print $3; exit}' "$RIDX"; }

    # ── 로컬 후보 목록: "NFC 상대경로 \t 실제 파일경로" ───────────────────
    # ⚠ macOS 는 한글 파일명을 **NFD** 로 저장하고, Drive 에 올라간 경로는 NFC 다.
    #   이 차이를 맞추지 않으면 해시 조회가 전건 빗나가 **매번 다시 올리고**(멱등 깨짐)
    #   Drive 에 같은 파일의 NFC/NFD 두 경로가 쌓인다 — Notion 게시에서 겪은 것과 같은 결함이다
    #   (issue #21·#22). 비교 키와 **업로드 대상 경로 양쪽**을 NFC 로 고정한다.
    #   경로는 로컬 실제 경로를 그대로 쓰고, 원격 경로만 NFC 로 만든다.
    LOCLIST="$(gd_tmp)"
    { for e in $exts; do find "$SRC" -type f -name "*.$e" 2>/dev/null; done; } \
      | NP_SRC_DIR="$SRC" "$PS_PY" -c '
import os, sys, unicodedata
src = os.environ["NP_SRC_DIR"].rstrip("/") + "/"
for line in sys.stdin:
    f = line.rstrip("\n")
    if not f:
        continue
    rel = f[len(src):] if f.startswith(src) else os.path.basename(f)
    sys.stdout.write(unicodedata.normalize("NFC", rel) + "\t" + f + "\n")
' > "$LOCLIST"

    pushlist="$(gd_tmp)"; conflicts=""; cnt_skip=0
    {
      while IFS=$'\t' read -r rel f; do
        [ -n "$rel" ] && [ -f "$f" ] || continue
        lh="$(local_md5 "$f")"; rh="$(rmd5 "$rel")"
        # 해시가 같으면 전송하지 않는다 — 원격의 실제 해시라 매니페스트가 어긋날 여지가 없다.
        if [ -n "$lh" ] && [ "$lh" = "$rh" ]; then cnt_skip=$((cnt_skip+1)); continue; fi
        # 내용이 다르고 원격이 더 최신이면 남이 고쳤을 수 있다 — 덮어쓰기 전에 알린다.
        if [ -n "$rh" ]; then
          rt="$(rmt "$rel")"; lt="$(fmtime "$f")"
          if [ -n "$rt" ] && [ -n "$lt" ] && [ "$rt" -gt "$lt" ] 2>/dev/null; then
            conflicts="$conflicts\n    · $rel  (Drive 원본이 더 최신 — 다른 사람이 수정했을 수 있음)"
          fi
        fi
        printf '%s\t%s\n' "$rel" "$f" >> "$pushlist"
      done < "$LOCLIST"
    }
    rm -f "$LOCLIST"

    if [ -n "$conflicts" ]; then
      echo "[gdrive] ⚠ 충돌 가능 — Drive 원본이 로컬보다 최신인 파일이 있습니다:" >&2
      printf "%b\n" "$conflicts" >&2
      echo "    → 그대로 push 하면 Drive 최신본을 덮어씁니다 (덮어쓰기 전 Drive 측 .bak-* 백업 생성)." >&2
      echo "    → 먼저 'pull' 로 받아 비교하길 권장합니다." >&2
      if [ "${PS_GDRIVE_YES:-}" = "1" ]; then
        echo "[gdrive] PS_GDRIVE_YES=1 — 충돌 덮어쓰기 승인됨, push 진행" >&2
      else
        printf "    계속 push 하시겠습니까? (y/N): " >&2
        # ⚠ 무한 대기 금지 — 제어 터미널이 붙은 백그라운드·스케줄러 실행에서는 /dev/tty 가
        #   열리지만 아무도 답하지 않아 **동기화 전체가 멈춘다**. 답이 없으면 헤드리스로 간주해
        #   E16 으로 빠져나가고 사용자에게 보고한다. 기다리는 것보다 알리는 편이 낫다.
        if read -r -t "${PS_GDRIVE_PROMPT_TIMEOUT:-30}" _ans </dev/tty 2>/dev/null; then :; else _ans="__NOTTY__"; fi
        case "$_ans" in
          y|Y) echo "[gdrive] 사용자 확인 — push 진행" >&2 ;;
          __NOTTY__)
            echo "[gdrive][E16] ✗ push 충돌 미해결 — 대화형 확인 불가(헤드리스). 위 충돌 목록을 사용자에게 보고하세요." >&2
            echo "      사용자 승인 후 덮어쓰기: PS_GDRIVE_YES=1 …/gdrive_sync.sh push   /  먼저 받기: …/gdrive_sync.sh pull" >&2
            rm -f "$RIDX" "$pushlist"; exit 16 ;;
          *) echo "[gdrive] push 취소 (충돌 회피)"; rm -f "$RIDX" "$pushlist"; exit 0 ;;
        esac
      fi
    fi

    [ "$cnt_skip" -gt 0 ] && echo "[gdrive] 동일 내용(해시 일치) $cnt_skip 개 스킵 — Drive 에 이미 있음"
    cnt=0; fail=0
    while IFS=$'\t' read -r rel f; do
      [ -n "$rel" ] || continue
      if [ -n "$conflicts" ] && printf '%b' "$conflicts" | grep -qF "· $rel "; then
        "$RCLONE" moveto "$RD/$rel" "$RD/$rel.bak-$(date +%s)" >/dev/null 2>&1
      fi
      # 원본은 로컬 실제 경로(NFD 일 수 있음), 대상은 NFC — 저장되는 값이 항상 NFC 다.
      if "$RCLONE" copyto "$f" "$RD/$rel" >/dev/null 2>&1; then cnt=$((cnt+1))
      else fail=$((fail+1)); echo "[gdrive] ⚠ 업로드 실패: $rel" >&2; fi
    done < "$pushlist"
    rm -f "$RIDX" "$pushlist"
    [ "$fail" -gt 0 ] && { echo "[gdrive] ⚠ push 일부 실패 ($fail 건)" >&2; exit 14; }
    if [ "$cnt" -gt 0 ]; then echo "[gdrive] ✓ push 완료 ($cnt 파일)"
    else echo "[gdrive] ✓ push 완료 (전송할 신규/변경 파일 없음 — 전부 최신)"; fi
    ;;

  pull)
    remote_ok || exit $?
    mkdir -p "$SRC"
    # ⚠ **배열로 넘긴다.** 따옴표 없는 `$inc` 는 셸이 **실행 디렉터리에 대해 글로빙**한다 —
    #   사업 루트에 pdf 가 하나만 있어도 `--include *.pdf` 가 `--include 그파일명` 으로 바뀌어
    #   나머지 pdf 를 전부 건너뛴 채 「✓ 완료」를 보고했다. 여러 개면 rclone 인자 초과로 실패했다.
    inc=()
    for e in $exts; do inc+=(--include "*.$e"); done
    # --checksum: 크기·시각이 아니라 해시로 판정 — 변경된 것만 내려온다.
    # --use-json-log: 건수를 **구조화된 로그**에서 읽는다. 사람이 읽는 문구를 파싱하면
    #   rclone 이 문구를 바꾼 날 「0 파일」이라는 틀린 수치를 조용히 보고하게 된다.
    OUT="$("$RCLONE" copy "$RD" "$SRC" --checksum "${inc[@]}" --stats 0 -v --use-json-log 2>&1)"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "[gdrive] ⚠ pull 실패:" >&2; printf '%s\n' "$OUT" | tail -5 >&2; exit 14
    fi
    # 셀 수 없으면 **세지 못했다고 말한다.** 틀린 수치보다 모른다는 편이 낫다.
    cnt="$(printf '%s' "$OUT" | "$PS_PY" -c '
import json, sys
seen_json = False
n = 0
raw = sys.stdin.read()
if not raw.strip():
    print(0); raise SystemExit          # 출력 자체가 없으면 전송이 없었던 것
for line in raw.splitlines():
    line = line.strip()
    if not line:
        continue
    try: d = json.loads(line)
    except Exception: continue
    seen_json = True
    if str(d.get("msg", "")).startswith("Copied"):
        n += 1
print(n if seen_json else "unknown")
' 2>/dev/null)"
    case "$cnt" in
      ''|unknown) echo "[gdrive] ✓ pull 완료 (건수 미상 — rclone 로그를 해석하지 못했습니다)" ;;
      *)          echo "[gdrive] ✓ pull 완료 (${cnt} 파일 — 변경분만)" ;;
    esac
    ;;

  setup-remote)
    gd_setup_remote; exit $?
    ;;

  *) echo "사용: gdrive_sync.sh init | push | pull | status | doctor [--quick] | setup-remote | push-file <파일> <경로>" >&2; exit 1 ;;
esac
