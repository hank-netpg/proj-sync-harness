#!/usr/bin/env bash
# proj-sync: 프로젝트 초기화 — .proj-sync/config.json + .env + .gitignore 스캐폴드
# 비대화형: 인자/환경변수로 받음. 대화형 프롬프트는 Claude(init 커맨드)가 수행.
# 사용: init.sh  (환경변수 PS_PROJECT_ID, PS_GH_ORG, PS_GH_REPO, PS_SLACK_TEAM, PS_SLACK_CH, PS_NOTION_DS 등)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# config.sh 의 PS_PY(python 실행기) / PATH 보강만 활용 (ps_load_config 는 호출 안 함)
. "$HERE/lib/config.sh"
. "$HERE/lib/scaffold.sh"   # ps_scaffold_project — config_migrate.sh 와 공유(드리프트 방지)
ROOT="${PS_INIT_ROOT:-$PWD}"
mkdir -p "$ROOT/.proj-sync"

# 지금 도는 사본의 정체를 먼저 밝힌다 — 버전만으로는 어느 사본인지 모른다(사본이 둘일 수 있다).
#   (2026-08-07 실측: ~/.claude/plugins/proj-sync 의 0.1.0 사본으로 init 돼 스캐폴드 22개 키가 누락됐는데,
#    로그·산출물 어디에도 버전이 없어 원인을 잘못 진단했다 — issue #14)
PS_PLUGIN_VERSION="$(ps_plugin_version)"; export PS_PLUGIN_VERSION
echo "[proj-sync] init v${PS_PLUGIN_VERSION}  (사본: $(ps_plugin_root))"

CFG="$ROOT/.proj-sync/config.json"
if [ -f "$CFG" ] && [ "${PS_FORCE:-0}" != "1" ]; then
  echo "[proj-sync] 이미 존재: $CFG (덮어쓰려면 PS_FORCE=1)"; exit 0
fi

# 레지스트리에서 기존 프로젝트 선택 시 PS_* 자동 채움(각자 새로 생성 방지 — 일관성 유지)
if [ -n "${PS_FROM_REGISTRY:-}" ]; then
  echo "[proj-sync] 레지스트리에서 '$PS_FROM_REGISTRY' 설정을 불러옵니다…"
  eval "$(bash "$HERE/registry.sh" get "$PS_FROM_REGISTRY")"
fi

# ⚠ 구분자에 따옴표 필수(<<'PY'). 따옴표가 없으면 셸이 본문을 확장해 **주석 속 역따옴표까지 실행**한다.
#   (2026-08-27 실측: :87 의 `rclone config` 가 실제로 돌아, rclone 이 깔린 머신에서 그 출력이
#    파이썬 소스에 치환돼 SyntaxError → config.json 이 만들어지지 않고 init 이 중단됐다. 대화형
#    셸에서는 rclone 이 입력을 기다려 그대로 멈췄다 — issue #38. rclone 이 없는 머신에서는 빈
#    문자열로 치환돼 아무 일도 없었기에 여태 드러나지 않았다.)
#   본문은 셸 확장을 쓰지 않는다 — 값은 os.environ.get 과 sys.argv 로만 들어온다.
#   tests/test_heredoc_safety.sh 가 이 불변식을 지킨다.
"$PS_PY" - "$CFG" <<'PY'
import json,os,sys,datetime
PLUG_VER=os.environ.get("PS_PLUGIN_VERSION","unknown")
TODAY=datetime.date.today().isoformat()
cfg={
 "version":1,
 # _init — 이 config 를 만든 플러그인 사본. "version":1 은 스키마 버전 리터럴이라 사본을 구분하지 못한다.
 #   plugin_version/at = 마지막 init, created_* = 최초 init(재init 으로 정상화한 사업을 구분).
 "_init":{"plugin_version":PLUG_VER,"at":TODAY,"created_version":PLUG_VER,"created_at":TODAY},
 "project":{"id":os.environ.get("PS_PROJECT_ID","myproject"),
            "name":os.environ.get("PS_PROJECT_NAME",""),
            "root_page_title":os.environ.get("PS_ROOT_PAGE","[Proj]"+os.environ.get("PS_PROJECT_ID","myproject"))},
 # GitHub = 마크다운(.md)·소스코드만. 사무파일(hwp/doc/ppt/xls/pdf 등)은 Google Drive 전담 → LFS 불필요(빈 배열).
 "github":{"org":os.environ.get("PS_GH_ORG",""),"repo":os.environ.get("PS_GH_REPO",""),
           "visibility":os.environ.get("PS_GH_VIS","private"),
           "lfs_extensions":[],
           "office_exts":["hwp","hwpx","doc","docx","ppt","pptx","xls","xlsx","pdf","png","jpg","jpeg","gif","zip"]},
 "slack":{"team_id":os.environ.get("PS_SLACK_TEAM",""),"channel_id":os.environ.get("PS_SLACK_CH",""),
          "token_ref":"env:PROJ_SYNC_SLACK_BOT_TOKEN","download_dir":"slack-files",
          "filename_pattern":"{file_id}__{name}","inventory_csv":"FILE_INVENTORY.csv"},
 "categories":[
   {"key":"01_제안요청서_RFP","exts":["hwp"]},
   {"key":"02_제안서_PPTX","exts":["pptx","ppt"]},
   {"key":"03_견적_인프라","exts":["xlsx","xls"]},
   {"key":"04_이메일_HTML","exts":["html","htm","eml"]},
   {"key":"05_실적_기타","exts":["pdf"]},
   {"key":"06_이미지_캡처","exts":["png","jpg","jpeg","gif"]},
   {"key":"99_기타","exts":["*"],"default":True}
 ],
 # provider=claude_ai_mcp — 게시는 로그인한 사용자의 claude.ai Notion 커넥터가 한다(v1.21.0).
 #   REST(팀 토큰)는 opt-in: 사람이 "notion_api" 로 바꿔 쓴다. PRESERVE 에 있어 재init 시 기존 값 보존.
 #   (v1.8.1~v1.20.3 의 "auto" 는 토큰이 있으면 REST 로 승격했다 — 지금은 auto 도 MCP 로 해석한다.)
 "notion":{"enabled":os.environ.get("PS_NOTION_DS","")!="","provider":"claude_ai_mcp",
           "data_source_id":os.environ.get("PS_NOTION_DS",""),
           "properties":{"title":"문서명","type":"유형","status":"상태",
                         "project":"프로젝트","applies_to":"적용대상","parent":"상위 항목"},
           # 게시 대상 집합 — 종전에는 init 이 이걸 쓰지 않아 신규 사업이 doctor 의
           #   「게시 대상 미정의」로 시작했고, 사람이 표준값을 손으로 옮겨 적어야 했다.
           #   globs = notion-publish 스킬의 표준값. exclude_globs 는 두 부류를 뺀다:
           #     · reports/  = 시점 기록(소급 갱신 대상 아님)
           #     · 스캐폴드 안내문 README 2건 = init 이 만든 규약 안내이지 산출물이 아니다.
           #       (빼지 않으면 신규 사업이 「게시 안 됨」으로 시작한다 — issue #12)
           #   하위 폴더에 사람이 만든 README 는 * 가 아닌 정확 경로 지정이라 계속 게시된다.
           "publish":{"globs":["reference/drafts/**/*.md","reference/management/**/*.md"],
                      "exclude_globs":["reference/management/reports/**/*.md",
                                       "reference/drafts/README.md",
                                       "reference/management/README.md"]}},
 "mentions":{},
 # 생애주기 — Notion 수행 프로젝트 DB '상태' 미러(제안·수주·수행중·완료·보류·실주). SDLC는 수행중 내부 stage.
 "lifecycle":{"phase":os.environ.get("PS_PHASE","제안"),
              "sdlc_stages":["착수","분석","설계","구현","종료"]},
 # WBS — profile(b2g/b2b/internal) 선택 + 담당자. tasks 는 PM 에이전트가 표준 마스터에서 전개.
 #   base_date=W1 기준일(주→날짜 파생), meta=WBS 개요, tasks=상세(revision build_wbs_xlsx.py 의 SSOT).
 "wbs":{"profile":os.environ.get("PS_PROFILE","b2g"),
        "owners":[],"base_date":os.environ.get("PS_WBS_BASE",""),"meta":{},"tasks":[]},
 # Google Drive — 대용량 산출물 저장소(v1.19.0 에서 NAS 대체).
 #   전송은 rclone 이 한다 — claude.ai Drive 커넥터에는 로컬 경로 업로드가 없어
 #   파일을 base64 로 컨텍스트에 통과시켜야 하고, 대용량이 이 저장소의 존재 이유이기 때문이다.
 #   remote 는 머신당 1회 `gdrive_sync.sh setup-remote` 가 만든다(v1.21.0 — 본인 Google 계정
 #   개인 OAuth 단일 경로). 비밀은 rclone 이 보관하므로 .env 불요.
 "gdrive":{"enabled":os.environ.get("PS_GDRIVE_TEAM","")!="",
           "remote":os.environ.get("PS_GDRIVE_REMOTE","gdrive"),
           "team_folder":os.environ.get("PS_GDRIVE_TEAM",""),
           "team_drive_id":os.environ.get("PS_GDRIVE_TEAM_DRIVE_ID",""),
           "root_folder_id":os.environ.get("PS_GDRIVE_ROOT_FOLDER_ID",""),
           "base_path":os.environ.get("PS_GDRIVE_BASE","{team_folder}/{project_id}"),
           "upload_exts":["hwp","hwpx","doc","docx","ppt","pptx","xls","xlsx","pdf","png","jpg","jpeg","gif","zip"]}
}
# ── PS_FORCE 재init: 사람이 채운 값을 잃지 않는다 ─────────────────────────
# 규칙 하나로 통일한다 — **env 로 명시 지정하지 않았고 기존값이 있으면 기존값을 유지**.
#   종전에는 이 규칙이 키마다 손으로 쓰인 if 문이었고, 목록에서 빠진 키(notion.*)는 조용히
#   ""·없음 으로 덮였다. 로그는 "기존 WBS·단계·작성자 보존됨" 이라 말해 손실을 가렸다.
#   (2026-08-07 실측: notion.project_tag·root_page_id·publish 소실 → 게시가 조용히 멈춤 — issue #13)
#   같은 유형의 손실 경로가 github.org/repo·slack.team_id/channel_id·project.name 에도 있었다.
# (경로, env 이름) — env=None 은 도구가 만들지 않는 사용자 데이터(항상 보존).
PRESERVE=[
 ("project.name","PS_PROJECT_NAME"), ("project.root_page_title","PS_ROOT_PAGE"),
 ("github.org","PS_GH_ORG"), ("github.repo","PS_GH_REPO"), ("github.visibility","PS_GH_VIS"),
 ("slack.team_id","PS_SLACK_TEAM"), ("slack.channel_id","PS_SLACK_CH"),
 ("notion.data_source_id","PS_NOTION_DS"),
 ("notion.project_tag",None), ("notion.root_page_id",None), ("notion.publish",None), ("notion.provider",None),
 ("lifecycle.phase","PS_PHASE"),
 ("wbs.profile","PS_PROFILE"), ("wbs.base_date","PS_WBS_BASE"),
 ("wbs.tasks",None), ("wbs.owners",None), ("wbs.meta",None),
 ("mentions",None), ("gdrive","PS_GDRIVE_TEAM"),
 # PS_GDRIVE_TEAM 으로 블록을 새로 쓸 때도 공유 드라이브 ID 는 지키지 않으면 remote 가 다시 필요해진다.
 ("gdrive.team_drive_id","PS_GDRIVE_TEAM_DRIVE_ID"), ("gdrive.root_folder_id","PS_GDRIVE_ROOT_FOLDER_ID"),
]
# 플러그인 소유 기본값 — 일부러 보존하지 않는다(갱신돼야 개선이 전파된다). 대신 갱신 사실을 로그로 남긴다.
PLUGIN_OWNED=["categories","github.lfs_extensions","github.office_exts",
              "lifecycle.sdlc_stages","gdrive.upload_exts"]

def dig(d,path):
    cur=d
    for k in path.split("."):
        if not isinstance(cur,dict) or k not in cur: return None
        cur=cur[k]
    return cur
def put(d,path,val):
    ks=path.split("."); cur=d
    for k in ks[:-1]: cur=cur.setdefault(k,{})
    cur[ks[-1]]=val
def empty(v): return v is None or v=="" or v==[] or v=={}
def label(path,val):
    return path+"("+str(len(val))+")" if isinstance(val,(list,dict)) and val else path
def brief(v):
    s=json.dumps(v,ensure_ascii=False) if not isinstance(v,str) else v
    return s if len(s)<=40 else s[:37]+"…"

p=sys.argv[1]
old={}
if os.path.exists(p):
    try: old=json.load(open(p,encoding="utf-8"))
    except Exception: old={}

kept=[]; overridden=[]; refreshed=[]
if old:
    for path,ev in PRESERVE:
        ov=dig(old,path)
        if empty(ov): continue
        envv=os.environ.get(ev,"") if ev else ""
        if envv:                                   # env 가 명시됐다 → 새 값이 이긴다(단, 바뀐 것만 알린다)
            nv=dig(cfg,path)
            if nv!=ov: overridden.append((path,ov,nv))
            continue
        put(cfg,path,ov); kept.append((path,ov))
    # notion.properties 는 통째 보존이 아니라 키 단위 병합 — 컬럼명을 바꾼 사업의 값은 지키면서
    #   플러그인이 새로 추가한 프로퍼티 키는 받아야 한다(통째 보존이면 새 키가 영원히 안 붙는다).
    oldprops=dig(old,"notion.properties")
    if isinstance(oldprops,dict) and oldprops:
        merged=dict(cfg["notion"]["properties"]); merged.update(oldprops)
        if merged!=cfg["notion"]["properties"]: kept.append(("notion.properties",merged))
        cfg["notion"]["properties"]=merged
    # _init: 최초 init 기록은 이어받는다(없으면 이번 값이 최초).
    oi=old.get("_init") if isinstance(old.get("_init"),dict) else {}
    cfg["_init"]["created_version"]=oi.get("created_version") or oi.get("plugin_version") or PLUG_VER
    cfg["_init"]["created_at"]=oi.get("created_at") or oi.get("at") or TODAY
    for path in PLUGIN_OWNED:
        ov=dig(old,path)
        if ov is not None and ov!=dig(cfg,path): refreshed.append(path)
# notion.enabled 는 보존 결과를 반영해 재계산 — PS_NOTION_DS 유무로만 정하면
#   기존 data_source_id 를 보존하고도 enabled=false 가 되는 모순이 생긴다.
cfg["notion"]["enabled"]=not empty(cfg["notion"]["data_source_id"])

json.dump(cfg, open(p,"w"), ensure_ascii=False, indent=2)
# 로그는 **보존되지 않은 것까지** 말한다. 종전 메시지는 보존만 말해 손실을 가렸다.
if old:
    print("[proj-sync] config 갱신:", p)
    if kept:       print("             보존", str(len(kept))+":", " · ".join(label(k,v) for k,v in kept))
    if refreshed:  print("             갱신", str(len(refreshed))+":", " · ".join(refreshed), "(플러그인 기본값)")
    if overridden: print("             ⚠ env 로 덮어씀", str(len(overridden))+":",
                         " · ".join(k+" '"+brief(o)+"' → '"+brief(n)+"'" for k,o,n in overridden))
else:
    print("[proj-sync] config 생성:", p)
PY

# 폴더·파일 스캐폴드 — lib/scaffold.sh 공유(config_migrate.sh 가 같은 코드로 누락분을 보강한다).
#   있는 파일은 건드리지 않는다. 만든 것은 PS_SCAFFOLD_NEW 에 남는다.
ps_scaffold_project "$ROOT"
echo "[proj-sync] revision/ 스캐폴드 (history·wbs·요구사항추적표) — /ax:revision 으로 빌드"
echo "[proj-sync] revision/회의록/ 스캐폴드 (회의록 — 회의별 yml 추가 후 /ax:minutes 로 빌드, lxml·PyYAML 필요)"
echo "[proj-sync] revision/전제/ 스캐폴드 (사업 전제 — /ax:premise 로 빌드)"
echo "[proj-sync] deliverables/ 스캐폴드 (납품 Archive)"
echo "[proj-sync] reference/drafts/ 스캐폴드 (작업 초안 00~50·99)"
echo "[proj-sync] reference/management/ 스캐폴드 (4대 관리 schedule·risk·config·reports)"
[ -n "${PS_SCAFFOLD_NEW:-}" ] && echo "[proj-sync] 생성: $PS_SCAFFOLD_NEW"

# 셔임 생성·갱신 (~/.proj-sync/bin/ax — tasks.json 이 이 경로를 호출)
ps_write_shim
# 팀 토큰(Slack) 자동 확보 — 이미 캐시돼 있으면 네트워크 호출 없이 통과.
#   종전에는 ".env 토큰 입력" 안내로 끝나 수동 입력을 유도했으나, ax-harness 멤버면 입력이 불필요하다.
#   Notion 은 팀 토큰이 아니다 — 로그인한 사용자의 claude.ai 커넥터가 게시한다(v1.21.0).
if type ps_ensure_team_tokens >/dev/null 2>&1 && ps_ensure_team_tokens; then
  echo "[proj-sync] Slack 팀 토큰 확보됨 (${PS_GLOBAL_CRED:-$HOME/.proj-sync/credentials}) — 토큰 입력 불요"
  echo "[proj-sync] Notion 게시는 각자의 claude.ai Notion 커넥터가 담당 — Claude Code 에서 /mcp 로 연결 확인"
  echo "[proj-sync] Google Drive 는 rclone(본인 Google 계정) — 미설정이면 /ax:doctor 가 setup-remote 를 안내"
  echo "[proj-sync] 초기화 완료. 다음: /ax:doctor 로 연결 점검"
else
  echo "[proj-sync] ⚠ Slack 팀 토큰 미확보 — gh 로그인 또는 조직 권한을 확인하세요."
  echo "            gh auth login  →  /ax:auth   (그래도 안 되면 .env 에 직접 입력)"
  echo "[proj-sync] 초기화 완료. 다음: /ax:doctor 로 연결 점검"
fi
