#!/usr/bin/env python3
"""dispatch.py — 자율주행 dispatch 판정(결정론). SPEC §5.

드롭된 파일 목록 + config.phase → 파일별 (category·confidence·action) 판정.
action = 실행할 스킬 이름 | "ask"(HITL — 신뢰도 낮음/phase 불일치).
인지(실제 실행·질문)는 PM 에이전트가 이 판정을 받아 수행(A3).

usage: dispatch.py <file...>   (config .proj-sync/config.json 의 lifecycle.phase 사용)
출력: JSON [{file,category,confidence,phase,action,reason}]
"""
import sys, os, json, pathlib, re

CFG = json.loads(pathlib.Path(".proj-sync/config.json").read_text(encoding="utf-8")) if pathlib.Path(".proj-sync/config.json").exists() else {}
PHASE = (CFG.get("lifecycle") or {}).get("phase", "제안")
TAU = ((CFG.get("dispatch") or {}).get("confidence_threshold", 0.75))

# 카테고리 규칙: (확장자셋, 파일명 키워드, 콘텐츠 시그니처)
CATS = [
    ("RFP",        {"hwp", "hwpx"}, ["제안요청", "과업", "rfp"], ["제안요청", "과업내용", "제안서 작성"]),
    ("목차·분담",   {"xlsx", "xls"}, ["목차", "분담", "wbs"],     ["목차", "업무분장"]),
    ("예산",        {"xlsx", "xls"}, ["예산", "금액", "견적"],     ["예산", "배분", "공급가액"]),
    ("회의록",      {"yml", "yaml", "docx", "hwpx"}, ["회의록", "미팅", "minutes"], ["안건", "참석", "회의"]),
    ("요구사항",    {"json", "md"},  ["요구사항", "rtm", "requirement"], ["요구사항", "추적표"]),
    ("자산·실적",   {"pdf", "md"},   ["실적", "자산", "레퍼런스"], ["수행실적", "포트폴리오"]),
]
# dispatch 규칙표: (phase, category) → 스킬
RULES = {
    ("제안", "RFP"): "rfp-extract", ("제안", "목차·분담"): "toc", ("제안", "예산"): "manage-config",
    ("제안", "자산·실적"): "docquark", ("제안", "요구사항"): "toc",
    ("수행중", "회의록"): "manage-minutes", ("수행중", "요구사항"): "manage-revision",
    ("수행중", "목차·분담"): "manage-schedule",
}

def signal_content(path, sigs):
    try:
        head = pathlib.Path(path).read_bytes()[:2048].decode("utf-8", "ignore")
    except Exception:
        return 0
    return 1 if any(s in head for s in sigs) else 0

def classify(path):
    name = os.path.basename(path).lower()
    ext = name.rsplit(".", 1)[-1] if "." in name else ""
    best = (None, 0.0)
    for cat, exts, kws, sigs in CATS:
        em = 1 if ext in exts else 0
        km = 1 if any(k in name for k in kws) else 0
        cm = signal_content(path, sigs) if em or km else 0
        conf = 0.4 * em + 0.4 * km + 0.2 * cm
        if conf > best[1]:
            best = (cat, conf)
    return best

def main():
    out = []
    for f in sys.argv[1:]:
        cat, conf = classify(f)
        skill = RULES.get((PHASE, cat))
        if conf < TAU:
            action, reason = "ask", f"분류 신뢰도 {conf:.2f} < {TAU}"
        elif skill is None:
            action, reason = "ask", f"phase({PHASE})×category({cat}) 매핑 없음(불일치)"
        else:
            action, reason = skill, f"규칙 매칭"
        out.append({"file": os.path.basename(f), "category": cat, "confidence": round(conf, 2),
                    "phase": PHASE, "action": action, "reason": reason})
    print(json.dumps(out, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()
