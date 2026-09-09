#!/usr/bin/env bash
# proj-sync: 오피스 문서(hwp/hwpx/xlsx/docx/pptx) → 마크다운 변환
#   원본은 Google Drive(GitHub 제외)로 가므로, PM 에이전트가 읽을 수 있게 본문을 .md 로 추출.
#   변환본은 reference/_extracted/ 에 저장 → GitHub push 대상(정책: md=GitHub).
#   변환 도구가 없는 형식은 graceful skip(원본만 Google Drive 보관).
# 사용:
#   office_to_md.sh            # slack-files/ 전체 스캔해 신규/변경분 변환
#   office_to_md.sh <파일>     # 특정 파일 1개 변환
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/lib/config.sh"
set +e

# 단일 파일 모드는 config 없이도 동작(PL 이 임의 파일 변환). 전체 스캔 모드만 config 필요.
if [ $# -ge 1 ] && [ -f "$1" ]; then
  # 단일 파일: 출력은 그 파일이 속한 프로젝트 루트의 reference/_extracted (없으면 파일 옆)
  PS_ROOT="${PS_ROOT:-$(cd "$(dirname "$1")" && pwd)}"
  SRC_DIR="$(cd "$(dirname "$1")" && pwd)"
else
  ps_load_config || { echo "[o2md] config 로드 실패 (.proj-sync/config.json 필요, 또는 파일 1개를 인자로)" >&2; exit 1; }
  SRC_DIR="$(ps_cfg '.slack.download_dir')"; [ -n "$SRC_DIR" ] || SRC_DIR="slack-files"
  SRC_DIR="$PS_ROOT/$SRC_DIR"
fi
OUT_DIR="$PS_ROOT/reference/_extracted"
mkdir -p "$OUT_DIR"

# 단일 파일을 마크다운으로 변환. 성공 시 0, 미지원/실패 시 1.
#   $1=입력경로  $2=출력 md 경로
convert_one() {
  local src="$1" out="$2" ext
  ext="$(printf '%s' "${src##*.}" | tr 'A-Z' 'a-z')"
  case "$ext" in
    hwpx)
      "$PS_PY" - "$src" "$out" <<'PY'
import sys, zipfile, re
from xml.etree import ElementTree as ET
src, out = sys.argv[1], sys.argv[2]
try:
    z = zipfile.ZipFile(src)
    ln = lambda t: t.rsplit('}',1)[-1]
    def cell_text(cell):
        return " ".join("".join(t.itertext()) for t in cell.iter() if ln(t.tag)=="t").strip()
    def is_data_table(md_rows):
        # 레이아웃용 표(목차·여백) 배제: 2열 이상 + 빈 셀 비율 50% 미만 + 2행 이상
        if len(md_rows) < 2: return False
        cells=[c.strip() for r in md_rows for c in r.strip("|").split("|")]
        if not cells: return False
        ncol = md_rows[0].count("|")-1
        if ncol < 2: return False
        empty = sum(1 for c in cells if not c)
        return empty/len(cells) < 0.5
    out_parts=[]
    for n in sorted(x for x in z.namelist() if x.startswith("Contents/section") and x.endswith(".xml")):
        root = ET.fromstring(z.read(n).decode("utf-8","ignore"))
        # 표는 "실제 데이터 표"만 마크다운 표로. 그 외(레이아웃 표 포함)는 본문 텍스트로.
        for el in root.iter():
            if ln(el.tag)=="tbl":
                rows=[r for r in el.iter() if ln(r.tag)=="tr"]
                md_rows=[]
                for r in rows:
                    cells=[cell_text(c) for c in r.iter() if ln(c.tag)=="tc"]
                    if cells: md_rows.append("| "+" | ".join(cells)+" |")
                if md_rows and is_data_table(md_rows):
                    ncol=md_rows[0].count("|")-1
                    md_rows.insert(1, "|"+"---|"*ncol)
                    out_parts.append("\n".join(md_rows))
        # 본문 텍스트 (표 안 텍스트 포함 — 데이터표로 뽑힌 건 위에 별도로도 있음. 가독 위해 전체 텍스트 유지)
        body=[ "".join(el.itertext()) for el in root.iter() if ln(el.tag)=="t" ]
        text="\n".join(p for p in body if p.strip())
        if text.strip(): out_parts.append(text)
    full="\n\n".join(out_parts); full=re.sub(r"\n{3,}","\n\n",full)
    open(out,"w",encoding="utf-8").write(f"# (추출) {src.split('/')[-1]}\n\n> 원본은 Google Drive 보관. 본문·표 자동 추출본(검토 필요).\n\n{full}\n")
    sys.exit(0 if full.strip() else 1)
except Exception:
    sys.exit(1)
PY
      ;;
    hwp)
      # hwp(구버전 바이너리)는 표·서식 구조가 손실됨 → 변환하지 않고 hwpx 재업로드 안내.
      #   사용자가 한글에서 "다른 이름으로 저장 → .hwpx" 로 올리면 표까지 정상 추출됨.
      "$PS_PY" - "$src" "$out" <<'PY'
import sys, os
src, out = sys.argv[1], sys.argv[2]
name=os.path.basename(src)
open(out,"w",encoding="utf-8").write(
f"""# ⚠ 변환 보류: {name}

> **이 파일은 구버전 한글(.hwp) 형식이라 표·서식이 깨져 자동 변환하지 않았습니다.**
>
> ## 해결 방법 (사용자 작업)
> 1. 한글(한컴오피스)에서 이 파일을 엽니다.
> 2. **파일 → 다른 이름으로 저장 → 형식을 `한글 문서 (*.hwpx)`** 로 저장합니다.
> 3. 저장한 **`.hwpx` 파일을 같은 Slack 채널/폴더에 다시 올립니다.**
> 4. 다시 동기화하면 표·본문이 정상 추출되어 PM·PL 에이전트가 읽습니다.
>
> (원본 .hwp 는 Google Drive 에 그대로 보관됩니다.)
""")
sys.exit(0)
PY
      # 화면에도 안내 (사용자가 바로 인지)
      echo "  ⚠ ${src##*/} : 구버전 .hwp — 한글에서 .hwpx 로 저장 후 다시 올려주세요 (표·서식 보존)" >&2
      ;;
    xlsx)
      "$PS_PY" - "$src" "$out" <<'PY'
import sys
src, out = sys.argv[1], sys.argv[2]
try:
    import openpyxl
    wb=openpyxl.load_workbook(src, read_only=True, data_only=True)
    md=[f"# (추출) {src.split('/')[-1]}", "", "> 원본은 Google Drive 보관. 표 자동 추출본(검토 필요).", ""]
    for ws in wb.worksheets:
        md.append(f"## 시트: {ws.title}\n")
        rows=list(ws.iter_rows(values_only=True))
        rows=[r for r in rows if any(c is not None for c in r)]
        if not rows: continue
        for r in rows[:200]:
            md.append("| "+" | ".join("" if c is None else str(c) for c in r)+" |")
        md.append("")
    open(out,"w",encoding="utf-8").write("\n".join(md)+"\n")
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
      ;;
    docx)
      "$PS_PY" - "$src" "$out" <<'PY'
import sys
src, out = sys.argv[1], sys.argv[2]
try:
    import docx  # python-docx
    d=docx.Document(src)
    text="\n".join(p.text for p in d.paragraphs if p.text.strip())
    open(out,"w",encoding="utf-8").write(f"# (추출) {src.split('/')[-1]}\n\n> 원본은 Google Drive 보관. 본문 자동 추출본(검토 필요).\n\n{text}\n")
    sys.exit(0 if text.strip() else 1)
except Exception:
    sys.exit(1)
PY
      ;;
    pptx)
      "$PS_PY" - "$src" "$out" <<'PY'
import sys
src, out = sys.argv[1], sys.argv[2]
try:
    from pptx import Presentation
    p=Presentation(src); md=[f"# (추출) {src.split('/')[-1]}","","> 원본은 Google Drive 보관. 슬라이드 자동 추출본(검토 필요).",""]
    for i,sl in enumerate(p.slides,1):
        md.append(f"## 슬라이드 {i}")
        for sh in sl.shapes:
            if sh.has_text_frame:
                for para in sh.text_frame.paragraphs:
                    t="".join(r.text for r in para.runs).strip()
                    if t: md.append("- "+t)
            # 표가 있으면 마크다운 표로
            if getattr(sh, "has_table", False) and sh.has_table:
                for row in sh.table.rows:
                    md.append("| "+" | ".join(c.text.strip() for c in row.cells)+" |")
        md.append("")
    open(out,"w",encoding="utf-8").write("\n".join(md)+"\n")
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
      ;;
    pdf)
      "$PS_PY" - "$src" "$out" <<'PY'
import sys, re
src, out = sys.argv[1], sys.argv[2]
try:
    import pdfplumber
    pages=[]
    with pdfplumber.open(src) as pdf:
        for i,page in enumerate(pdf.pages,1):
            # 표 우선 추출 → 마크다운, 없으면 텍스트
            parts=[f"## p.{i}"]
            tables=page.extract_tables() or []
            for tb in tables:
                for row in tb:
                    cells=["" if c is None else str(c).replace("\n"," ").strip() for c in row]
                    parts.append("| "+" | ".join(cells)+" |")
            txt=(page.extract_text() or "").strip()
            if txt: parts.append(txt)
            pages.append("\n".join(parts))
    text="\n\n".join(pages); text=re.sub(r"\n{3,}","\n\n",text)
    open(out,"w",encoding="utf-8").write(f"# (추출) {src.split('/')[-1]}\n\n> 원본은 Google Drive 보관. PDF 자동 추출본(표·본문, 검토 필요).\n\n{text}\n")
    sys.exit(0 if text.strip() else 1)
except Exception:
    sys.exit(1)
PY
      ;;
    *) return 1 ;;
  esac
}

# 카운터 (process 보다 먼저 초기화 — set -u 대비)
CONV=0; SKIP=0
# 대상 결정: 인자 있으면 그 파일, 없으면 slack-files 전체 스캔
process() {
  local f="$1" rel base mdpath
  rel="${f#$SRC_DIR/}"
  # 파일명은 영문(ASCII)으로. 한글·특수문자는 _, 그래도 비면 원본명 해시.
  #   (원본 파일명은 변환된 .md 헤더에 보존됨)
  base="$("$PS_PY" - "$rel" <<'PY'
import sys, re, hashlib, os
rel=sys.argv[1]
stem, ext = os.path.splitext(os.path.basename(rel))   # 디렉터리 제외, 파일명만
catdir = os.path.dirname(rel).split('/')[0] if '/' in rel else ""
ext=ext.lstrip('.').lower()
# Slack file_id(F + 영숫자 8자+) 가 파일명에 있으면 그것을 우선 식별자로
m=re.search(r'F[A-Z0-9]{8,}', stem)   # Slack file_id (한글 인접이라 \b 미사용)
fid=m.group(0) if m else ""
# 카테고리 코드(01_ 등) 추출
catcode=""
mc=re.match(r'(\d{2})_', catdir) or re.match(r'(\d{2})_', stem)
if mc: catcode=mc.group(1)
# 영문 슬러그(남은 ASCII 영숫자)
asc=re.sub(r'[^A-Za-z0-9]+','_', stem).strip('_')
asc=re.sub(r'_{2,}','_', asc)
# 식별자 조합: [카테고리]_[fileid 또는 해시]_[확장자]
ident = fid or "doc"+hashlib.md5(rel.encode('utf-8')).hexdigest()[:6]
parts=[p for p in (catcode, ident, ext) if p]
print("_".join(parts))
PY
)"
  mdpath="$OUT_DIR/${base}.md"
  # 이미 변환됐고 원본이 더 안 새로우면 skip
  if [ -f "$mdpath" ] && [ "$mdpath" -nt "$f" ]; then return 0; fi
  if convert_one "$f" "$mdpath"; then
    echo "  ✓ ${rel} → reference/_extracted/${base}.md"
    CONV=$((CONV+1))
  else
    rm -f "$mdpath" 2>/dev/null
    echo "  - ${rel} (변환 미지원/도구없음 — 원본은 Google Drive 보관)"
    SKIP=$((SKIP+1))
  fi
}

if [ $# -ge 1 ] && [ -f "$1" ]; then
  SRC_DIR="$(dirname "$1")"; process "$1"
else
  [ -d "$SRC_DIR" ] || { echo "[o2md] $SRC_DIR 없음 (먼저 slack 다운로드)"; exit 0; }
  # 서브셸 변수 소실 방지: 프로세스 치환 대신 임시파일로 목록을 받아 현재 셸에서 루프
  _list="$(mktemp)"
  find "$SRC_DIR" -type f \( \
    -iname '*.hwp' -o -iname '*.hwpx' -o -iname '*.xlsx' -o -iname '*.docx' -o -iname '*.pptx' -o -iname '*.pdf' \) 2>/dev/null > "$_list"
  while IFS= read -r f; do [ -n "$f" ] && process "$f"; done < "$_list"
  rm -f "$_list"
fi
echo "[o2md] 변환 ${CONV}건 / 미지원·skip ${SKIP}건 → reference/_extracted/ (GitHub push 대상)"
