#!/usr/bin/env bash
# proj-sync: config·스캐폴드 마이그레이션 — **재init 없이** 플러그인 개선을 기존 사업에 닿게 한다.
#
# 불변식 (자동 실행의 유일한 안전 근거) — **additive only**:
#   · 없는 키만 추가한다. 있는 값은 읽기만 한다.
#   · 배열은 append 만 한다. 기존 원소를 지우거나 재정렬하지 않는다.
#   · 파일·폴더는 없는 것만 만든다.
#   그래서 키 이름 변경·삭제형 마이그레이션은 여기서 다루지 않는다(별도 설계 필요).
#
# 왜 필요했나: v1.15.0 이 고친 것(_init 기록·publish 표준블록·스캐폴드 README 게시 제외)은
#   재init 을 해야만 적용됐다. 재init 은 config 를 전면 재작성하는 경로라 사람에게 시키기 어렵고,
#   사용자 수 × 사업 수만큼 미적용이 남는다. (issue #16)
#
# 사용:  config_migrate.sh [--dry-run]      (doctor.sh 가 자동 호출)
#        PS_NO_MIGRATE=1 로 완전 차단.
# 종료코드: 0=정상(적용했든 안 했든) · 1=config 없음. **치명 아님** — 호출부를 막지 않는다.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
. "$HERE/lib/scaffold.sh"

DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
[ "${PS_NO_MIGRATE:-0}" = "1" ] && exit 0

ps_load_config >/dev/null 2>&1 || { echo "[proj-sync] config 없음 — 마이그레이션 건너뜀" >&2; exit 1; }

PS_PLUGIN_VERSION="$(ps_plugin_version)"; export PS_PLUGIN_VERSION
export PS_MIGRATE_DRY="$DRY"

# 1) config.json — additive 갱신
CHANGES="$("$PS_PY" - "$PS_CONFIG" <<'PY'
import json,os,sys,datetime
p=sys.argv[1]; VER=os.environ.get("PS_PLUGIN_VERSION","unknown"); TODAY=datetime.date.today().isoformat()
DRY=os.environ.get("PS_MIGRATE_DRY")=="1"
try: c=json.load(open(p,encoding="utf-8"))
except Exception as e:
    print("!config 읽기 실패: %s" % e); sys.exit(0)
done=[]

# _init — 이 config 를 만든 사본. 없으면 v1.14.0 이하로 만든 것이다(그 버전부터 기록이 생겼다).
#   created_version 을 unknown 으로 남겨 "언제부터 추적됐는지"를 잃지 않는다.
if not isinstance(c.get("_init"),dict):
    c["_init"]={"plugin_version":VER,"at":TODAY,
                "created_version":"unknown(<=1.14.0)","created_at":"unknown",
                "migrated_at":TODAY}
    done.append("_init 추가")
elif c["_init"].get("plugin_version")!=VER:
    c["_init"]["plugin_version"]=VER; c["_init"]["at"]=TODAY; c["_init"]["migrated_at"]=TODAY
    done.append("_init.plugin_version → "+VER)

n=c.setdefault("notion",{})
# provider — 키가 **없는** config 에만 기본값을 넣는다(불변식). 기존 "auto" 값은 그대로 두며,
#   그 의미는 읽는 쪽(doctor)이 v1.21.0 부터 MCP 로 해석한다(팀 REST 경로는 삭제됨).
if "provider" not in n:
    n["provider"]="claude_ai_mcp"; done.append("notion.provider 추가(claude_ai_mcp — 로그인 사용자의 커넥터가 게시)")
STD_GLOBS=["reference/drafts/**/*.md","reference/management/**/*.md"]
SCAFFOLD_EXCL=["reference/drafts/README.md","reference/management/README.md"]
REPORTS_EXCL="reference/management/reports/**/*.md"

# publish 블록 — 없으면 표준값. 있으면 **globs 는 손대지 않는다**(사업 커스터마이즈).
pub=n.get("publish")
if not isinstance(pub,dict) or not pub.get("globs"):
    n["publish"]={"globs":STD_GLOBS,"exclude_globs":[REPORTS_EXCL]+SCAFFOLD_EXCL}
    done.append("notion.publish 표준블록 추가")
else:
    ex=pub.get("exclude_globs")
    if not isinstance(ex,list): ex=[];
    add=[g for g in ([REPORTS_EXCL]+SCAFFOLD_EXCL) if g not in ex]
    if add:
        pub["exclude_globs"]=ex+add          # append 만 — 기존 원소 무변경
        done.append("publish.exclude_globs +%d" % len(add))

# gdrive 블록 — v1.19.0 에서 NAS(Synology)를 Google Drive 로 교체했다.
#   ⚠ 불변식 준수: **gdrive 를 추가만 하고 nas 는 지우지 않는다.** 삭제는 additive 가 아니다.
#     남은 nas 키는 읽는 코드가 없어 무해하며, 사람이 확인하고 지우도록 doctor 가 안내한다.
#   enabled 는 **false 로 둔다** — remote 는 머신당 1회 `rclone config` 가 필요하고,
#   그 전에 true 로 켜면 doctor 가 없는 설정을 문제로 보고하게 된다.
if not isinstance(c.get("gdrive"),dict):
    old=c.get("nas") if isinstance(c.get("nas"),dict) else {}
    c["gdrive"]={"enabled":False,
                 "remote":"gdrive",
                 "team_drive_id":"","root_folder_id":"",
                 # 팀 폴더명은 NAS 것을 물려받아 사람이 손댈 거리를 줄인다(없으면 빈 값).
                 "team_folder":old.get("team_folder",""),
                 "base_path":old.get("base_path","{team_folder}/{project_id}"),
                 "upload_exts":old.get("upload_exts",
                   ["hwp","hwpx","doc","docx","ppt","pptx","xls","xlsx","pdf","png","jpg","jpeg","gif","zip"])}
    done.append("gdrive 블록 추가(NAS 대체 · enabled=false — setup-remote 후 활성화)")
# gdrive 공유 드라이브 키(v1.21.0) — 없는 키만 추가. 인증은 개인 rclone OAuth 단일 경로라
#   auth 키를 추가하지 않는다. 기존 config 에 남은 auth 키는 지우지 않는다(additive) —
#   읽는 코드가 없고, doctor 가 확인·삭제를 안내한다.
g=c.get("gdrive")
if isinstance(g,dict):
    for k,v in (("team_drive_id",""),("root_folder_id","")):
        if k not in g:
            g[k]=v; done.append("gdrive.%s 추가" % k)

if done and not DRY:
    json.dump(c, open(p,"w"), ensure_ascii=False, indent=2)
for d in done: print(d)
PY
)"

# 2) 폴더·파일 스캐폴드 — 누락분만 (init.sh 와 같은 코드: lib/scaffold.sh)
#    실패를 삼키지 않는다. 종전 `2>/dev/null || true` 는 템플릿 누락·권한 오류를 통째로 지워
#    아무 출력 없이 통과했고, 사용자는 받지 못한 것을 받았다고 믿었다(운영성·"실패는 스스로를 알려야 한다").
#    "치명 아님"(호출부를 막지 않음)만 유지하고, 사유는 CHANGES 에 실어 doctor 출력에 드러낸다.
#    서브셸을 쓰지 않는다 — PS_SCAFFOLD_NEW 가 현재 셸에 남아야 한다.
if [ "$DRY" = "0" ]; then
  _SC_LOG="$(mktemp)"
  ps_scaffold_project "$PS_ROOT" 2>"$_SC_LOG"; _SC_RC=$?
  [ -n "${PS_SCAFFOLD_NEW:-}" ] && CHANGES="${CHANGES:+$CHANGES
}스캐폴드 생성: $PS_SCAFFOLD_NEW"
  if [ "$_SC_RC" != "0" ] || [ -s "$_SC_LOG" ]; then
    CHANGES="${CHANGES:+$CHANGES
}⚠ 스캐폴드 실패(rc=$_SC_RC) — $(tr '\n' ' ' < "$_SC_LOG" | cut -c1-200)"
  fi
  rm -f "$_SC_LOG"
fi

# 3) 보고 — 무엇을 바꿨는지 반드시 말한다. doctor 를 read-only 로 아는 사용자를 놀래지 않기 위함.
if [ -n "$CHANGES" ]; then
  if [ "$DRY" = "1" ]; then
    printf '[proj-sync] 마이그레이션 필요 (v%s) — 적용 예정:\n' "$PS_PLUGIN_VERSION"
  else
    printf '[proj-sync] config 마이그레이션 v%s 적용:\n' "$PS_PLUGIN_VERSION"
  fi
  printf '%s\n' "$CHANGES" | sed 's/^/             · /'
  [ "$DRY" = "0" ] && echo "             (기존 값은 건드리지 않았습니다. 끄려면 PS_NO_MIGRATE=1)"
fi
exit 0
