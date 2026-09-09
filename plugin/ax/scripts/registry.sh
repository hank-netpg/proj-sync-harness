#!/usr/bin/env bash
# proj-sync: 수행 프로젝트 레지스트리 — Notion 수행 프로젝트 DB의 GitHub 미러(registry.json) 조회/등록.
# 토큰 불요(기존 gh 인증 사용). 사용: registry.sh list | get <id> | clone <id> [dir] | append <project.json>
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"   # PS_PY, PATH 보강, ps_gh_file

REG_ORG="${PS_REGISTRY_ORG:-ax-harness}"
REG_REPO="${PS_REGISTRY_REPO:-proj-sync-registry}"
REG_FILE="${PS_REGISTRY_FILE:-registry.json}"

_fetch(){ ps_gh_file "$REG_ORG/$REG_REPO" "$REG_FILE"; }

# registry.json 을 받아 임시파일(RTMP)로 저장. 성공 0 / 조회 실패 1. (이후 "$PS_PY" - "$RTMP" 로 파싱)
_load_registry() {
  local raw; raw="$(_fetch || true)"
  [ -z "$raw" ] && return 1
  RTMP="$(mktemp)"; printf '%s' "$raw" > "$RTMP"; trap 'rm -f "$RTMP"' EXIT
}

cmd="${1:-list}"; shift || true
case "$cmd" in
  fetch) _fetch ;;

  list)
    if ! _load_registry; then
      echo "(레지스트리 조회 실패 — gh 로그인/접근 권한 또는 $REG_ORG/$REG_REPO 존재 여부 확인)"; exit 0
    fi
    "$PS_PY" - "$RTMP" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); ps=d.get("projects",[])
if not ps: print("(레지스트리에 프로젝트 없음)"); sys.exit(0)
print("# 등록된 수행 프로젝트 (updated %s)" % d.get("updated",""))
for i,p in enumerate(ps,1):
    gh=p.get("github") or {}
    repo=("%s/%s"%(gh.get("org",""),gh.get("repo",""))) if gh else "-"
    team=",".join(p.get("team") or []) or "-"
    print("%2d) %-12s %s  [%s] (%s)  %s" % (i,p.get("id",""),p.get("name",""),team,p.get("status",""),repo))
PY
    ;;

  get)   # registry.sh get <id> → init.sh 가 eval 할 PS_* export 라인 출력
    id="${1:?usage: registry.sh get <id>}"
    _load_registry || { echo "레지스트리 조회 실패(gh 인증/접근 확인)" >&2; exit 2; }
    PS_ID="$id" "$PS_PY" - "$RTMP" <<'PY'
import json,os,sys,shlex
d=json.load(open(sys.argv[1])); tid=os.environ["PS_ID"]
p=next((x for x in d.get("projects",[]) if x.get("id")==tid),None)
if not p: sys.stderr.write("레지스트리에 없음: %s\n"%tid); sys.exit(2)
gh=p.get("github") or {}; sl=p.get("slack") or {}; nt=p.get("notion") or {}
def e(k,v): print("export %s=%s" % (k, shlex.quote(v or "")))
e("PS_PROJECT_ID",   p.get("id"))
e("PS_PROJECT_NAME", p.get("name"))
e("PS_GH_ORG",       gh.get("org"))
e("PS_GH_REPO",      gh.get("repo"))
e("PS_GH_VIS",       gh.get("visibility") or "private")
e("PS_SLACK_TEAM",   sl.get("team_id"))
e("PS_SLACK_CH",     sl.get("channel_id"))
e("PS_NOTION_DS",    nt.get("data_source_id"))
e("PS_ROOT_PAGE",    (nt.get("root_page_title") or ("[Proj]"+(p.get("name") or p.get("id")))))
PY
    ;;

  append) # registry.sh append <project.json> → registry.json 에 upsert 후 push
    src="${1:?usage: registry.sh append <project.json>}"
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    git clone -q "https://github.com/$REG_ORG/$REG_REPO.git" "$tmp/repo"
    NEW="$src" TODAY="$(date +%F)" "$PS_PY" - "$tmp/repo/$REG_FILE" <<'PY'
import json,os,sys
path=sys.argv[1]; d=json.load(open(path)); new=json.load(open(os.environ["NEW"]))
ids={p.get("id") for p in d.get("projects",[])}
if new.get("id") in ids:
    d["projects"]=[new if p.get("id")==new["id"] else p for p in d["projects"]]
else:
    d.setdefault("projects",[]).append(new)
d["updated"]=os.environ["TODAY"]
json.dump(d,open(path,"w"),ensure_ascii=False,indent=2)
print("upsert:", new.get("id"))
PY
    ( cd "$tmp/repo" \
      && git add -A \
      && git -c user.name=proj-sync -c user.email=proj-sync@example.com commit -q -m "registry: upsert $(basename "$src" .json)" \
      && git push -q )
    echo "[proj-sync] registry.json 갱신·push 완료"
    ;;

  clone) # registry.sh clone <id> [dir] → 선택 프로젝트의 GitHub repo 를 clone (config·문서 일괄 확보)
    id="${1:?usage: registry.sh clone <id> [dir]}"
    _load_registry || { echo "레지스트리 조회 실패(gh 인증/접근 확인)" >&2; exit 2; }
    line="$(PS_ID="$id" "$PS_PY" - "$RTMP" <<'PY'
import json,os,sys
d=json.load(open(sys.argv[1])); tid=os.environ["PS_ID"]
p=next((x for x in d.get("projects",[]) if x.get("id")==tid),None)
if not p: sys.stderr.write("레지스트리에 없음: %s\n"%tid); sys.exit(2)
gh=p.get("github") or {}
if not gh.get("repo"): sys.stderr.write("이 프로젝트엔 GitHub repo가 없습니다: %s\n"%tid); sys.exit(3)
print("%s/%s" % (gh.get("org",""), gh.get("repo","")))
PY
)" || exit $?
    dir="${2:-${line##*/}}"   # 기본 폴더명 = repo 이름
    if [ -e "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
      echo "[proj-sync] '$dir' 가 비어있지 않습니다 — 다른 폴더명을 지정하세요." >&2; exit 4
    fi
    echo "[proj-sync] clone: $line → $dir"
    gh repo clone "$line" "$dir"
    # Slack 토큰은 .env 대신 전역 자동조회(/ax:auth)로 처리 → 여기선 .env 생성 안 함
    echo "[proj-sync] 완료 → cd \"$dir\" → /ax:doctor (Slack 토큰 자동조회) → /ax:sync"
    ;;

  setch) # registry.sh setch <id> <channel_id> [team_id] → registry.json 의 해당 프로젝트 slack 채널 갱신 후 push
    id="${1:?usage: registry.sh setch <id> <channel_id> [team_id]}"; ch="${2:?channel_id(C…) 필요}"; team="${3:-${PS_SLACK_TEAM:-}}"
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    git clone -q "https://github.com/$REG_ORG/$REG_REPO.git" "$tmp/repo"
    ID="$id" CH="$ch" TEAM="$team" TODAY="$(date +%F)" "$PS_PY" - "$tmp/repo/$REG_FILE" <<'PY'
import json,os,sys
path=sys.argv[1]; d=json.load(open(path))
for p in d.get("projects",[]):
    if p.get("id")==os.environ["ID"]:
        team=os.environ.get("TEAM") or (p.get("slack") or {}).get("team_id") or ""
        p["slack"]={"team_id":team,"channel_id":os.environ["CH"]}; break
else:
    sys.stderr.write("레지스트리에 없음: %s\n"%os.environ["ID"]); sys.exit(2)
d["updated"]=os.environ["TODAY"]
json.dump(d,open(path,"w"),ensure_ascii=False,indent=2); print("slack 채널 설정:",os.environ["ID"],"→",os.environ["CH"])
PY
    ( cd "$tmp/repo" && git add -A && git -c user.name=proj-sync -c user.email=proj-sync@example.com commit -q -m "registry: set slack channel for $id" && git push -q )
    echo "[proj-sync] registry.json slack 채널 갱신·push 완료 (사람용 SSOT인 Notion DB도 함께 갱신하세요 → registry-sync 권장)"
    ;;

  *) echo "사용: registry.sh list | get <id> | clone <id> [dir] | setch <id> <channel_id> | append <project.json>" >&2; exit 1 ;;
esac
