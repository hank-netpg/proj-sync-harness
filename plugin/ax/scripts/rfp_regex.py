#!/usr/bin/env python3
"""rfp_regex.py — RFP 텍스트에서 요구사항 ID 카드 1차 추출(정규식). P0 스텁.
출력: proposal/_extracted/cards.json  [{"id","context"}]. 서브에이전트가 category/summary/quote 정제."""
import re, json, sys, pathlib
src = pathlib.Path(sys.argv[1] if len(sys.argv)>1 else "proposal/_extracted/rfp.txt")
txt = src.read_text(encoding="utf-8") if src.exists() else ""
# ID 패턴: 3대문자-3숫자 (SFR-001, PLR-005 …)
cards, seen = [], set()
for m in re.finditer(r"([A-Z]{3})-(\d{3})", txt):
    rid = f"{m.group(1)}-{m.group(2)}"
    if rid in seen: continue
    seen.add(rid)
    ctx = txt[m.start(): m.start()+300].replace("\n"," ")
    cards.append({"id": rid, "context": ctx})
out = pathlib.Path("proposal/_extracted/cards.json"); out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(cards, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"[rfp_regex] 요구사항 카드 {len(cards)}건 → {out}")
