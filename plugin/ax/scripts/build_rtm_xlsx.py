#!/usr/bin/env python3
"""요구사항추적표(RTM) 빌더 — revision/요구사항추적표/rtm.data.json(SSOT)
→ revision/…/요구사항추적표.md(작업) + deliverables/요구사항추적표.xlsx(납품·2시트: 추적표·충족도집계).

대응방안의 여러 줄(제시안 불릿)은 json 문자열(\\n)로 보존 → md 는 <br>, xlsx 는 셀 내 개행.
경로: env PS_ROOT 사용(revision_build.sh 설정). 단독 실행 시 CWD 상위에서 .proj-sync 탐색.
"""
import json
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "lib"))
from lib_xlsx import write_workbook  # noqa: E402

HDR = ["대분류", "중분류", "ID", "세부 요구사항", "제안서 근거(원문 인용·페이지)", "충족도", "대응방안(제시안)"]
LEVEL_ORDER = ["완전", "부분", "미흡"]


def _find_root():
    r = os.environ.get("PS_ROOT")
    if r and os.path.isfile(os.path.join(r, ".proj-sync", "config.json")):
        return r
    d = os.getcwd()
    while True:
        if os.path.isfile(os.path.join(d, ".proj-sync", "config.json")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    sys.exit("[build_rtm] .proj-sync/config.json 를 찾지 못함 (PS_ROOT 미설정)")


def _tracked(level):
    return "해당없음" not in (level or "")


def build(reqs):
    table = [HDR]
    for r in reqs:
        table.append([r.get("group", ""), r.get("subgroup", ""), r.get("id", ""),
                      r.get("text", ""), r.get("evidence", ""), r.get("level", ""), r.get("plan", "")])

    counts = Counter(r.get("level", "") for r in reqs)
    total = sum(v for k, v in counts.items() if _tracked(k))
    summary = [["충족도", "건수", "비율(추적 대상 기준)"]]
    for lv in LEVEL_ORDER:
        n = counts.get(lv, 0)
        summary.append([lv, n, f"{round(n / total * 100)}%" if total else "-"])
    for lv, n in counts.items():
        if not _tracked(lv):
            summary.append([lv, n, "-"])
    summary.append(["합계(추적 대상)", total, "100%" if total else "-"])
    return table, summary


def write_md(path, table, summary, n):
    lines = ["# 요구사항추적표 (RTM)", "",
             f"> 생성: `/ax:revision`(build_rtm_xlsx.py) · SSOT: `revision/요구사항추적표/rtm.data.json` · "
             f"요구사항 {n}건 · **md·xlsx 는 파생물, 편집은 json 에서**", "",
             "## 충족도 집계", "",
             "| " + " | ".join(summary[0]) + " |",
             "| " + " | ".join(["---"] * len(summary[0])) + " |"]
    for r in summary[1:]:
        lines.append("| " + " | ".join(str(c) for c in r) + " |")
    lines += ["", "## 추적표", "",
              "| " + " | ".join(HDR) + " |", "| " + " | ".join(["---"] * len(HDR)) + " |"]
    for r in table[1:]:
        lines.append("| " + " | ".join(str(c).replace("|", "\\|").replace("\n", "<br>") for c in r) + " |")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    root = _find_root()
    data_path = os.path.join(root, "revision", "요구사항추적표", "rtm.data.json")
    if not os.path.isfile(data_path):
        sys.exit(f"[build_rtm] 없음: {data_path} (/ax:init 로 스캐폴드)")
    with open(data_path, encoding="utf-8") as f:
        reqs = json.load(f).get("requirements", []) or []
    out_dir = os.path.dirname(data_path)                        # 작업(리뷰) md
    deliv_dir = os.path.join(root, "deliverables")              # 납품(Archive) xlsx
    os.makedirs(deliv_dir, exist_ok=True)
    table, summary = build(reqs)
    md_path = os.path.join(out_dir, "요구사항추적표.md")
    xlsx_path = os.path.join(deliv_dir, "요구사항추적표.xlsx")
    write_md(md_path, table, summary, len(reqs))
    write_workbook(xlsx_path, [("요구사항추적표", table), ("충족도 집계", summary)])
    print(f"[rtm] 요구사항 {len(reqs)}건 · 시트 2개 → revision/요구사항추적표/요구사항추적표.md + deliverables/요구사항추적표.xlsx")


if __name__ == "__main__":
    main()
