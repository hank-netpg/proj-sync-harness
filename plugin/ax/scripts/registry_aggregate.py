#!/usr/bin/env python3
"""registry_aggregate.py — Leader-Worker 교차집계. SPEC §8 / 원안 PDF.

Worker(팀원 계정별): 자기 사업 폴더 → 프로젝트 요약(진척·리스크·전제·마감) emit.
Leader(registry): 여러 요약 → 전 사업 교차 조망(리스크·마감 D-day·정체) rollup.
A7 인증경계(org 멤버십) 유지, 계정별 Worker 토큰(병목 해소, 결정2).

usage:
  registry_aggregate.py emit   [projectDir=.]           # Worker: → registry/{id}.summary.json
  registry_aggregate.py rollup <summary.json...>        # Leader: → registry/_dashboard.md
"""
import sys, json, datetime, pathlib, glob

def load(p, d=None):
    p = pathlib.Path(p)
    if not p.exists(): return d
    return json.loads(p.read_text(encoding="utf-8")) if p.suffix == ".json" else p.read_text(encoding="utf-8")

def emit(pdir="."):
    pdir = pathlib.Path(pdir)
    cfg = load(pdir / ".proj-sync/config.json", {}) or {}
    proj = cfg.get("project", {}); life = cfg.get("lifecycle", {})
    wbs = load(pdir / "revision/wbs/wbs.data.json") or cfg.get("wbs", {}) or {}
    tasks = [t for t in wbs.get("tasks", []) if t.get("level") == 3]
    done = sum(1 for t in tasks if t.get("status") == "완료")
    prog = round(done / len(tasks), 3) if tasks else 0.0
    today = datetime.date.today().isoformat()
    delayed = [t.get("id") for t in tasks if t.get("status") != "완료" and str(t.get("due", "")) and str(t.get("due")) < today]
    # 리스크·미확정전제: hitl_scan 결과 있으면 사용, 없으면 간이
    hitl = load(pdir / "reference/management/_hitl.json", [])
    risks = [q.get("detail") for q in hitl if q.get("severity") == "high"][:3]
    if not risks and delayed:
        risks = [f"지연 {len(delayed)}건"]
    # 마감: proposal.deadline 또는 최근접 due
    dl = (cfg.get("proposal") or {}).get("deadline") or (min((str(t.get("due")) for t in tasks if t.get("due")), default=None))
    summary = {"id": proj.get("id"), "repo": f"{cfg.get('github',{}).get('org')}/{cfg.get('github',{}).get('repo')}",
               "phase": life.get("phase"), "worker": cfg.get("authorization", {}).get("worker_account", "self"),
               "summary": {"진척": prog, "리스크_top": risks, "지연": delayed,
                           "미확정전제": None, "마감": dl}, "updated": today}
    out = pathlib.Path("registry"); out.mkdir(exist_ok=True)
    fp = out / f"{proj.get('id','proj')}.summary.json"
    fp.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[registry emit] {proj.get('id')} · 진척 {prog:.0%} · 지연 {len(delayed)} · 마감 {dl} → {fp}")
    return summary

def rollup(files):
    projs = [load(f) for f in files if load(f)]
    today = datetime.date.today()
    def dday(dl):
        try: return (datetime.date.fromisoformat(str(dl)[:10]) - today).days
        except Exception: return None
    projs.sort(key=lambda p: (dday(p["summary"].get("마감")) if dday(p["summary"].get("마감")) is not None else 999))
    lines = ["# 전 사업 교차 조망 (Leader Aggregation)", f"> {today} · 프로젝트 {len(projs)}건\n",
             "| 사업 | phase | 진척 | 지연 | 마감(D-day) | 리스크 Top |", "|---|---|---|---|---|---|"]
    for p in projs:
        s = p["summary"]; dd = dday(s.get("마감"))
        lines.append(f"| {p.get('id')} | {p.get('phase')} | {s.get('진척',0):.0%} | {len(s.get('지연',[]))} | "
                     f"{s.get('마감') or '-'}{f' (D{dd:+})' if dd is not None else ''} | {'; '.join(s.get('리스크_top',[])) or '-'} |")
    out = pathlib.Path("registry"); out.mkdir(exist_ok=True)
    (out / "_dashboard.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"[registry rollup] {len(projs)}개 사업 → registry/_dashboard.md")
    print("\n".join(lines))

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "emit"
    if cmd == "emit": emit(sys.argv[2] if len(sys.argv) > 2 else ".")
    elif cmd == "rollup": rollup(sys.argv[2:] or glob.glob("registry/*.summary.json"))
    else: print("usage: registry_aggregate.py emit [dir] | rollup <summary.json...>"); sys.exit(1)
