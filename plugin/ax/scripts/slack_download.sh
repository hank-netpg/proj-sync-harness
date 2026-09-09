#!/usr/bin/env bash
# proj-sync: Slack 채널 전 파일 다운로드 → 카테고리 분류 + FILEID__ 접두사 + CSV 매니페스트
# config.json 기반. 멱등(state.json의 done 목록 기준 신규만).
# 사용: slack_download.sh   (프로젝트 루트 또는 하위에서)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
. "$HERE/lib/slack_api.sh"

ps_load_config || exit 1

# ── 원격 최신 반영(pull --rebase): GitHub SSOT 단방향 설계상 작업 전 로컬을 최신화한다.
#    dedup(디스크+CSV seed)이 최신 커밋 상태를 봐야, 다른 팀원이 이미 올린 파일을
#    stale 로 인해 재다운로드/중복 생성하는 것을 막는다. (실패해도 로컬 기준 계속)
if git -C "$PS_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
   && git -C "$PS_ROOT" remote get-url origin >/dev/null 2>&1 \
   && git -C "$PS_ROOT" ls-remote --heads origin main 2>/dev/null | grep -q .; then
  echo "[proj-sync] 원격 최신 반영: git pull --rebase origin main"
  git -C "$PS_ROOT" pull --rebase --autostash origin main \
    || echo "[proj-sync] ⚠️ git pull 실패 — 로컬 기준으로 계속(push 단계에서 재확인)."
fi

PS_SLACK_TOKEN="$(ps_slack_token)"
ps_slack_init_token || exit 1

# config 3개 값을 python 1회 호출로 모음
{ IFS= read -r CH; IFS= read -r DL_DIR; IFS= read -r CSV_NAME; } \
  < <(ps_cfg_get '.slack.channel_id' '.slack.download_dir' '.slack.inventory_csv')
OUT_DIR="$PS_ROOT/$DL_DIR"
CSV="$PS_ROOT/$CSV_NAME"
STATE="$PS_ROOT/.proj-sync/state.json"
[ -f "$STATE" ] || echo '{"downloaded":[]}' > "$STATE"
mkdir -p "$OUT_DIR"

[ -z "$CH" ] && { echo "[proj-sync] channel_id 미설정"; exit 1; }
echo "[proj-sync] 채널 $CH 파일 목록 수집..."
FILES_JSON="$(ps_slack_list_files "$CH")"

# 파일목록 JSON 은 argv 가 아니라 임시파일로 넘긴다.
#   리눅스는 인자 "하나"의 길이를 MAX_ARG_STRLEN(=128KB)로 제한한다(ARG_MAX 총량과 별개).
#   파일이 쌓인 채널(한글 파일명 기준 대략 40건 이상)은 목록 JSON 이 이를 넘겨
#   "Argument list too long" 으로 죽는다. 임시파일 경유는 길이 제한이 없다.
FILES_TMP="$(mktemp)"; trap 'rm -f "$FILES_TMP"' EXIT
printf '%s' "$FILES_JSON" > "$FILES_TMP"

# 파이썬으로 카테고리 분류 + 다운로드 + CSV + state 갱신
PS_SLACK_TOKEN="$PS_SLACK_TOKEN" "$PS_PY" - "$FILES_TMP" "$OUT_DIR" "$CSV" "$STATE" "$PS_CONFIG" <<'PY'
import json, sys, os, subprocess, csv, unicodedata
from datetime import datetime, timezone, timedelta

# macOS/APFS 는 파일명을 NFD(완전분해형)로 저장하며, 255바이트 길이 제한도
# NFD 인코딩 기준으로 적용된다. 한글이 많은 파일명은 NFC 기준으로는 짧아 보여도
# NFD 로는 최대 2배 가까이 늘어나 한도를 넘을 수 있고, 이 경우 curl/OS 가 에러 없이
# 파일명을 조용히 잘라 CSV 매니페스트 경로와 실제 파일이 어긋나게 된다(내용은 무결).
NFD_LIMIT = 240  # 255 바이트 한도에 여유를 둔 안전선

def nfd_len(s):
    return len(unicodedata.normalize("NFD", s).encode("utf-8"))

def fit_nfd(fid, name, limit=NFD_LIMIT):
    ext = os.path.splitext(name)[1]
    base = name[:-len(ext)] if ext else name
    full = f"{fid}__{base}{ext}"
    if nfd_len(full) <= limit:
        return full
    while base and nfd_len(f"{fid}__{base}{ext}") > limit:
        base = base[:-1]
    return f"{fid}__{base}{ext}"

files     = json.load(open(sys.argv[1], encoding="utf-8"))
out_dir   = sys.argv[2]
csv_path  = sys.argv[3]
state_path= sys.argv[4]
cfg       = json.load(open(sys.argv[5]))
token     = os.environ.get("PS_SLACK_TOKEN","")
KST = timezone(timedelta(hours=9))

cats = cfg.get("categories", [])
default_cat = next((c["key"] for c in cats if c.get("default")), "99_기타")
def categorize(name):
    ext = os.path.splitext(name)[1].lstrip(".").lower()
    for c in cats:
        if c.get("default"): continue
        if ext in [e.lower() for e in c.get("exts",[])]:
            return c["key"]
    return default_cat

state = json.load(open(state_path))
done = set(state.get("downloaded", []))

# state.json 은 gitignore 되어 clone 시 없을 수 있음(→ done 이 비어 전부 재다운로드되는 중복 버그).
# 커밋에 딸려오는 내구성 소스(디스크 실체 + CSV 매니페스트)로 done 을 보강해 멱등성을 보장한다.
#  1) 디스크: out_dir 아래 이미 존재하는 "{file_id}__..." 파일들의 file_id
if os.path.isdir(out_dir):
    for _r,_d,_fn in os.walk(out_dir):
        for _n in _fn:
            if _n.startswith("."): continue
            if "__" in _n: done.add(_n.split("__",1)[0])
#  2) CSV: 이전 매니페스트의 file_id 컬럼(원본이 Google Drive 로 이동해 로컬엔 없는 경우까지 커버)
if os.path.exists(csv_path):
    try:
        with open(csv_path, newline="", encoding="utf-8") as _cf:
            for _row in csv.DictReader(_cf):
                _fid=(_row.get("file_id") or "").strip()
                if _fid: done.add(_fid)
    except Exception as _e:
        print(f"  [warn] CSV 매니페스트 읽기 실패(무시): {_e}")

rows=[]; new=0; skip=0
for f in files:
    fid=f["id"]; name=f.get("name","").strip() or fid
    if fid in done:
        skip+=1; continue
    cat=categorize(name)
    d=os.path.join(out_dir,cat); os.makedirs(d,exist_ok=True)
    # 파일명 정규화 (경로 탐색 방지: '/', '\\', '..' 제거)
    safe_name=os.path.basename(name).replace("/", "_").replace("\\", "_")
    safe=fit_nfd(fid, safe_name)
    if safe != f"{fid}__{safe_name}":
        print(f"  [name-fit] {fid} 파일명이 APFS NFD 255바이트 한도 초과 → 축약 저장 (원본은 CSV original_name 에 보존)")
    url=f.get("url_private_download") or f.get("url_private")
    if not url:
        print(f"  [no-url] {fid} {name}"); continue
    dst=os.path.join(d,safe)
    # 토큰을 argv(ps 노출) 대신 stdin config(-K -)로 전달
    proc=subprocess.run(["curl","-sS","-fL","-K","-",
                         "-w","%{content_type}",url,"-o",dst],
                        input=f'header = "Authorization: Bearer {token}"\n',
                        capture_output=True, text=True)
    if proc.returncode!=0:
        print(f"  [fail] {fid} {name} (curl rc={proc.returncode}) — 토큰/권한 확인 필요")
        if os.path.exists(dst): os.remove(dst)
        continue
    ctype=(proc.stdout or "").strip().lower()
    sz=os.path.getsize(dst) if os.path.exists(dst) else 0
    ext=os.path.splitext(name)[1].lstrip(".").lower()
    # 인증 실패 시 200/HTML 로그인 페이지가 올 수 있음 → done 등록 전 차단
    if sz==0 or (ctype.startswith("text/html") and ext not in ("html","htm")):
        print(f"  [skip-bad] {fid} {name} (ctype={ctype}, size={sz}) — 채널 멤버십/토큰 확인")
        if os.path.exists(dst): os.remove(dst)
        continue
    # 콘텐츠 해시(sha256) — Drive 중복 제거(멱등)의 고유값. 다운로드 시 1회 계산해 재계산 회피.
    import hashlib
    h=hashlib.sha256()
    with open(dst,"rb") as _fp:
        for _chunk in iter(lambda: _fp.read(1<<20), b""): h.update(_chunk)
    sha=h.hexdigest()
    ts=f.get("created",0)
    dt=datetime.fromtimestamp(ts,KST).strftime("%Y-%m-%d %H:%M") if ts else ""
    # ⚠ os.path.relpath 는 Windows 에서 역슬래시를 돌려준다. 이 값은 CSV 의 saved_path 이자
    #   gdrive-manifest.tsv 의 **키**라, mac 에서 만든 `a/b` 와 win 에서 만든 `a\b` 가 다른 키가 되어
    #   중복 제거가 깨지고 같은 파일이 매번 다시 올라간다(2026-08-26 실측: 32행 오염).
    #   저장소에 남는 값은 항상 POSIX 로 고정한다.
    relpath=os.path.relpath(dst, os.path.dirname(out_dir)).replace(os.sep, "/")
    rows.append({"category":cat,"file_id":fid,"original_name":name,
                 "saved_path":relpath,
                 "size_bytes":sz,"sha256":sha,"uploaded_kst":dt,"uploader":f.get("user","")})
    done.add(fid); new+=1
    print(f"  ↓ [{cat}] {name} ({sz}B)")

# 해시 매니페스트 (경로\tsha256) — Slack 유입분의 콘텐츠 지문.
#   .proj-sync/gdrive-manifest.tsv 에 누적. (Drive push 자체의 멱등은 rclone 체크섬이 담당)
try:
    proot=os.path.dirname(out_dir)
    man=os.path.join(proot,".proj-sync","gdrive-manifest.tsv")
    os.makedirs(os.path.dirname(man),exist_ok=True)
    seen={}
    if os.path.exists(man):
        for ln in open(man,encoding="utf-8"):
            p=ln.rstrip("\n").split("\t")
            if len(p)==2: seen[p[0]]=p[1]
    for r in rows: seen[r["saved_path"]]=r["sha256"]
    with open(man,"w",encoding="utf-8") as fp:
        for p,s in sorted(seen.items()): fp.write(f"{p}\t{s}\n")
except Exception as _e:
    print(f"  [warn] gdrive-manifest 기록 실패: {_e}")

# CSV (append 또는 신규). 기존 파일의 헤더가 현재 스키마와 다르면(예: 과거본엔 sha256 컬럼 없음)
# 그대로 append 하면 헤더와 행의 컬럼이 어긋난다 → 헤더가 다르면 기존 행을 새 스키마로 재기록 후 append.
fields=["category","file_id","original_name","saved_path","size_bytes","sha256","uploaded_kst","uploader"]
exists=os.path.exists(csv_path)
old_header=None
if exists:
    with open(csv_path,newline="",encoding="utf-8") as fp:
        old_header=next(csv.reader(fp),None)
if exists and old_header==fields:
    with open(csv_path,"a",newline="",encoding="utf-8") as fp:
        csv.DictWriter(fp,fieldnames=fields,extrasaction="ignore").writerows(rows)
else:
    old_rows=[]
    if exists:  # 헤더 불일치 → 기존 행을 읽어 새 스키마로 이관(누락 컬럼은 빈값)
        with open(csv_path,newline="",encoding="utf-8") as fp:
            old_rows=list(csv.DictReader(fp))
    with open(csv_path,"w",newline="",encoding="utf-8") as fp:
        w=csv.DictWriter(fp,fieldnames=fields,extrasaction="ignore")
        w.writeheader()
        for _o in old_rows: w.writerow({k:_o.get(k,"") for k in fields})
        w.writerows(rows)

state["downloaded"]=sorted(done)
json.dump(state, open(state_path,"w"), ensure_ascii=False, indent=2)
print(f"\n[proj-sync] 신규 {new}건 / 기존 {skip}건 스킵 / 총 {len(files)}건. → {out_dir}")
PY

# ── 오피스 문서 → 마크다운 자동 변환 (PM 에이전트가 읽을 수 있게) ──
#   원본 사무파일은 Google Drive 로 가지만, 본문 추출본(.md)은 reference/_extracted/ → GitHub.
echo
echo "[proj-sync] 오피스 문서 → 마크다운 변환 (PM 분석용)…"
bash "$HERE/office_to_md.sh" 2>/dev/null || echo "[proj-sync] (변환 일부 미지원 — 원본은 Google Drive 보관)"
