#!/usr/bin/env bash
# parse_doc.sh <파일> [out=proposal/_extracted/rfp.txt] — RFP 원문 텍스트 추출(부수효과)
set -euo pipefail
F="${1:?사용: parse_doc.sh <hwpx|pdf> [out]}"; OUT="${2:-proposal/_extracted/rfp.txt}"; mkdir -p "$(dirname "$OUT")"
ext="${F##*.}"; ext="$(echo "$ext" | tr 'A-Z' 'a-z')"
case "$ext" in
  hwpx) python3 - "$F" "$OUT" <<'PY'
import sys,zipfile,re
f,out=sys.argv[1],sys.argv[2]
z=zipfile.ZipFile(f); xml="".join(z.read(n).decode('utf-8','ignore') for n in z.namelist() if re.search(r'Contents/section\d+\.xml',n))
t=[re.sub(r'<[^>]+>','',p).replace('&amp;','&').replace('&lt;','<').replace('&gt;','>') for p in re.findall(r'<hp:t[^>]*>(.*?)</hp:t>',xml,re.S)]
open(out,'w').write("\n".join(t)); print(f"[parse_doc] hwpx {len(t)} 문단 → {out}")
PY
  ;;
  pdf) python3 - "$F" "$OUT" <<'PY'
import sys
try:
    from pypdf import PdfReader
except Exception:
    print("[parse_doc] pypdf 미설치 — pip install --user pypdf 후 재시도, 또는 PDF 재업로드"); sys.exit(1)
r=PdfReader(sys.argv[1]); open(sys.argv[2],'w').write("\n".join((p.extract_text() or "") for p in r.pages)); print("[parse_doc] pdf → "+sys.argv[2])
PY
  ;;
  *) echo "[parse_doc] 미지원 확장자: $ext (hwpx/pdf)"; exit 1;;
esac
