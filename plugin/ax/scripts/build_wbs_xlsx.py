#!/usr/bin/env python3
"""WBS 빌더 — .proj-sync/config.json 의 wbs(SSOT) → revision/wbs/WBS.md(작업) + deliverables/WBS.xlsx(납품).

revision 축의 표준화기. WBS 는 config.wbs(tasks·base_date·meta)가 SSOT, 이 스크립트가
리뷰용 md 와 납품용 xlsx(4시트: 개요·WBS상세·Gantt·요구사항 커버리지)를 파생 생성한다.
롤업·일정(주→날짜)·Gantt·커버리지는 leaf(레벨3)에서 재계산 — leaf 만 고치면 자동 반영.

경로: env PS_ROOT(프로젝트 루트)·PS_CONFIG(config 경로) 사용(revision_build.sh 가 설정).
단독 실행 시엔 CWD 상위에서 .proj-sync/config.json 을 탐색한다.
"""
import datetime
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "lib"))
from lib_xlsx import write_workbook  # noqa: E402

DETAIL_HDR = ["WBS", "Phase", "레벨", "작업명", "활동·산출물", "요구사항ID", "RTM REQ-ID",
              "아키텍처", "담당", "시작W", "종료W", "기간(주)", "일정(날짜)", "공수(M/D)", "선행"]


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
    sys.exit("[build_wbs] .proj-sync/config.json 를 찾지 못함 (PS_ROOT 미설정)")


def _int(v):
    return v if isinstance(v, int) else None


def _parse_base(base_date):
    try:
        return datetime.date(*map(int, base_date.split("-")[:3])) if base_date else None
    except (ValueError, AttributeError):
        return None


def _daterange(base, s, e):
    if not (base and s and e):
        return ""
    a = base + datetime.timedelta(days=(s - 1) * 7)
    b = base + datetime.timedelta(days=(e - 1) * 7 + 6)
    return f"{a.month}/{a.day}~{b.month}/{b.day}"


def _is_descendant(child, parent):
    return child == parent or child.startswith(parent + ".")


def _rollup(task, leaves):
    kids = [l for l in leaves if _is_descendant(l["wbs"], task["wbs"])]
    starts = [_int(l.get("start_w")) for l in kids if _int(l.get("start_w"))]
    ends = [_int(l.get("end_w")) for l in kids if _int(l.get("end_w"))]
    effort = sum(_int(l.get("effort")) or 0 for l in kids)
    s = min(starts) if starts else _int(task.get("start_w"))
    e = max(ends) if ends else _int(task.get("end_w"))
    return s, e, effort


def build(wbs):
    meta = wbs.get("meta", {}) or {}
    tasks = wbs.get("tasks", []) or []
    base = _parse_base(wbs.get("base_date"))
    leaves = [t for t in tasks if t.get("level") == 3]

    detail = [DETAIL_HDR]
    for t in tasks:
        lvl = t.get("level") or 3
        if lvl == 3:
            s, e, eff = _int(t.get("start_w")), _int(t.get("end_w")), _int(t.get("effort"))
        else:
            s, e, eff = _rollup(t, leaves)
        dur = (e - s + 1) if (s and e) else ""
        leaf = lvl == 3
        detail.append([
            t.get("wbs", ""), t.get("phase", ""), lvl,
            "  " * (lvl - 1) + (t.get("name") or ""),
            t.get("output", "") if leaf else "",
            t.get("req_id", "") if leaf else "",
            t.get("rtm_req_id", "") if leaf else "",
            t.get("arch", "") if leaf else "",
            t.get("owner", "") if leaf else "",
            s or "", e or "", dur, _daterange(base, s, e), eff or "",
            t.get("pred", "") if leaf else "",
        ])

    max_w = max((_int(t.get("end_w")) or 0 for t in tasks), default=0)
    gantt = [["WBS", "Phase", "작업명", "담당", "공수"] + [f"W{i}" for i in range(1, max_w + 1)]]
    for l in leaves:
        s, e = _int(l.get("start_w")), _int(l.get("end_w"))
        bars = ["■" if (s and e and s <= i <= e) else "" for i in range(1, max_w + 1)]
        gantt.append([l.get("wbs", ""), l.get("phase", ""), l.get("name", ""),
                      l.get("owner", ""), _int(l.get("effort")) or ""] + bars)

    cov = {}
    for l in leaves:
        rid = (l.get("req_id") or "").strip()
        if rid:
            cov.setdefault(rid, []).append(l["wbs"])
    coverage = [["요구사항ID", "대응 WBS 수", "대응 WBS", "커버 여부"]]
    for rid in sorted(cov):
        coverage.append([rid, len(cov[rid]), ", ".join(cov[rid]), "OK"])
    if cov:
        coverage.append([f"합계: {len(cov)}종 커버", "", "", "누락 0"])

    overview = [["항목", "내용"]] + [[k, v] for k, v in meta.items()]
    overview += [["", ""],
                 ["⚠ 이 xlsx", "파생물 — SSOT는 config.wbs(.proj-sync/config.json). 편집 후 /ax:revision 로 재생성"]]

    sheets = [("개요", overview), ("WBS 상세", detail), ("Gantt", gantt), ("요구사항 커버리지", coverage)]
    return meta, detail, len(leaves), sheets


def write_md(path, meta, detail, n_leaf):
    title = (list(meta.values())[0] if meta else "") or "WBS"
    lines = [f"# WBS — {title}", "",
             f"> 생성: `/ax:revision`(build_wbs_xlsx.py) · SSOT: `.proj-sync/config.json` wbs · "
             f"과업 {len(detail) - 1}행(세부 {n_leaf}건) · **md·xlsx 는 파생물, 편집은 config.wbs 에서**", ""]
    for k in ("기준 시작일(W1)", "내부 목표 완료", "사업 종료(계약 종료)", "공식 결과물"):
        if k in meta:
            lines.append(f"- **{k}**: {meta[k]}")
    lines += ["", "| " + " | ".join(DETAIL_HDR) + " |",
              "| " + " | ".join(["---"] * len(DETAIL_HDR)) + " |"]
    for r in detail[1:]:
        lines.append("| " + " | ".join(str(c).replace("|", "\\|").replace("\n", "<br>") for c in r) + " |")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def main():
    root = _find_root()
    cfg_path = os.environ.get("PS_CONFIG") or os.path.join(root, ".proj-sync", "config.json")
    with open(cfg_path, encoding="utf-8") as f:
        wbs = json.load(f).get("wbs", {}) or {}
    out_dir = os.path.join(root, "revision", "wbs")       # 작업(리뷰) md
    deliv_dir = os.path.join(root, "deliverables")        # 납품(Archive) xlsx
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(deliv_dir, exist_ok=True)
    meta, detail, n_leaf, sheets = build(wbs)
    md_path = os.path.join(out_dir, "WBS.md")
    xlsx_path = os.path.join(deliv_dir, "WBS.xlsx")
    write_md(md_path, meta, detail, n_leaf)
    write_workbook(xlsx_path, sheets)
    print(f"[wbs] 과업 {len(detail) - 1}행(세부 {n_leaf}) · 시트 {len(sheets)}개 → revision/wbs/WBS.md + deliverables/WBS.xlsx")


if __name__ == "__main__":
    main()
