#!/usr/bin/env python3
"""evaluate_aggregate.py — 3-Agent 평가 집계(결정론) + 종료 판정.

usage:
  # 1) rubric 생성:  evaluate_aggregate.py rubric   (proposal/toc.json#평가배점 → proposal/eval/rubric.json)
  # 2) 집계:         evaluate_aggregate.py agg <위원findings.json...>  (→ proposal/eval/{round}.json, 종료판정 출력)

집계 규칙: 항목별 배점 만점에서 위원 감점 합산(항목 배점 하한). 종합 = Σ 항목점수.
종료: score>=target OR round>=max_rounds OR Δ<min_delta (config.proposal.eval).
H2: 이 스크립트는 '계산'만 — 채점(위원)·수정은 에이전트.
"""
import json, sys, pathlib, glob

PROP = pathlib.Path("proposal")
EVAL = PROP / "eval"; EVAL.mkdir(parents=True, exist_ok=True)

def load(p, default=None):
    p = pathlib.Path(p)
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else default

def gen_rubric():
    toc = load(PROP / "toc.json", {})
    배점 = toc.get("평가배점", {})
    # 기술 항목(가격 제외)만 채점 대상
    항목 = [{"key": k, "배점": v, "만점조건": f"{k} 요구 전 항목 구현방안·근거·검증방법 구비"}
            for k, v in 배점.items() if k != "가격"]
    rubric = {"항목": 항목, "총점": sum(x["배점"] for x in 항목), "가격": 배점.get("가격", 10)}
    (EVAL / "rubric.json").write_text(json.dumps(rubric, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[rubric] 항목 {len(항목)} · 기술총점 {rubric['총점']} → eval/rubric.json")
    return rubric

def cfg_eval():
    c = load(".proj-sync/config.json", {}) or {}
    e = (c.get("proposal") or {}).get("eval") or {}
    return e.get("target_score", 90), e.get("max_rounds", 5), e.get("min_delta", 0.5)

def aggregate(finding_files):
    rubric = load(EVAL / "rubric.json") or gen_rubric()
    만점 = {x["key"]: x["배점"] for x in rubric["항목"]}
    위원 = []
    # per-위원 per-항목 감점 수집 (독립 평가)
    위원항목감점 = []  # [{항목키: 감점}]
    for f in finding_files:
        data = load(f, [])
        items = data if isinstance(data, list) else data.get("findings", [])
        wid = pathlib.Path(f).stem
        wmap = {}
        for it in items:
            k = it.get("항목키"); d = float(it.get("감점", it.get("감점(음수)", 0)) or 0)
            if k in 만점:
                wmap[k] = wmap.get(k, 0.0) + d
        위원항목감점.append(wmap)
        위원.append({"id": wid, "감점": round(sum(wmap.values()), 2), "findings": items})
    # 항목점수 = 위원별 항목점수(max(0, 만점+감점))의 평균 — 3인 독립평가 평균(합산 아님)
    항목점수 = {}
    for k, full in 만점.items():
        per = [max(0.0, full + w.get(k, 0.0)) for w in 위원항목감점] or [full]
        항목점수[k] = round(sum(per) / len(per), 2)
    score = round(sum(항목점수.values()), 2)
    # round 번호 = 기존 eval/{n}.json 최대+1
    rounds = [int(p.stem) for p in EVAL.glob("*.json") if p.stem.isdigit()]
    rnd = (max(rounds) + 1) if rounds else 0
    target, maxr, mind = cfg_eval()
    prev = load(EVAL / f"{rnd-1}.json") if rnd > 0 else None
    delta = round(score - prev["score"], 2) if prev else None
    stop = (score >= target) or (rnd + 1 >= maxr) or (delta is not None and delta < mind)
    개선 = sorted([{"page_id": it.get("page_id"), "개선지시": it.get("개선지시"), "감점": it.get("감점")}
                  for w in 위원 for it in w["findings"] if it.get("개선지시")],
                 key=lambda x: x.get("감점", 0))[:10]
    out = {"round": rnd, "score": score, "target": target, "항목점수": 항목점수,
           "위원": 위원, "delta": delta, "stop": stop, "개선_dispatch": 개선}
    (EVAL / f"{rnd}.json").write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[agg] round {rnd} · 종합 {score}/{rubric['총점']} (목표 {target})"
          + (f" · Δ{delta:+}" if delta is not None else "")
          + f" · {'STOP' if stop else '계속(개선 dispatch)'}")
    if not stop:
        print(f"[agg] 개선 대상 {len(개선)}건 → 페이지별 수정 에이전트 dispatch")
    return out

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "rubric"
    if cmd == "rubric":
        gen_rubric()
    elif cmd == "agg":
        aggregate(sys.argv[2:] or glob.glob(str(EVAL / "w_*.json")))
    else:
        print("usage: evaluate_aggregate.py rubric | agg <findings.json...>"); sys.exit(1)
