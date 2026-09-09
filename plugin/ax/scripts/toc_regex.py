#!/usr/bin/env python3
"""toc_regex.py — RFP/목차 텍스트에서 chapter>section 후보 1차 추출. P0 스텁."""
import re, json, sys, pathlib
txt = pathlib.Path(sys.argv[1] if len(sys.argv)>1 else "proposal/_extracted/rfp.txt")
t = txt.read_text(encoding="utf-8") if txt.exists() else ""
chaps=[]
for m in re.finditer(r"([ⅠⅡⅢⅣⅤⅥⅦ])\.\s*([^\n]{2,30})", t):
    chaps.append({"roman":m.group(1),"title":m.group(2).strip()})
out=pathlib.Path("proposal/_extracted/toc_regex.json"); out.parent.mkdir(parents=True,exist_ok=True)
out.write_text(json.dumps(chaps,ensure_ascii=False,indent=2),encoding="utf-8")
print(f"[toc_regex] 장 후보 {len(chaps)}건 → {out}")
