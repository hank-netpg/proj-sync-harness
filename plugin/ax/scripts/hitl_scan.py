#!/usr/bin/env python3
"""hitl_scan.py — human-in-the-loop 질문 트리거 결정론 스캐너. SPEC §6.

사업 폴더의 SSOT를 스캔해 '사용자 결정이 필요한 지점'을 탐지 → 질문 목록(JSON) 산출.
PM 에이전트가 이 목록을 받아 AskUserQuestion(옵션형)으로 사용자에 질문, 피드백을 SSOT에 반영.
탐지만(결정론) — 질문·반영은 에이전트(A3).

트리거(6종): 전제 미합의 · 전제 stale · WBS 지연 · 요구사항 미매핑 · 평가규정 미확인 · dispatch 불확실.
usage: hitl_scan.py   (CWD=사업 폴더)
출력: JSON [{trigger,severity,detail,question,sink}]
"""
import json, subprocess, datetime, pathlib, re

def load(p, d=None):
    p = pathlib.Path(p)
    if not p.exists(): return d
    t = p.read_text(encoding="utf-8")
    if p.suffix == ".json": return json.loads(t)
    return t

def yaml_min(text):
    """premise.yml 최소 파서(PyYAML 없으면) — 상태/확인시점/근거 필드만."""
    try:
        import yaml; return yaml.safe_load(text)
    except Exception:
        return None

Q = []
def add(trigger, sev, detail, question, sink):
    Q.append({"trigger": trigger, "severity": sev, "detail": detail, "question": question, "sink": sink})

def git_mtime(path):
    try:
        out = subprocess.run(["git", "log", "-1", "--format=%cI", "--", path],
                             capture_output=True, text=True).stdout.strip()
        return out or None
    except Exception:
        return None

# 1·2) 전제 미합의 / stale
pm = load("revision/전제/premise.yml")
data = yaml_min(pm) if pm else None
if isinstance(data, dict):
    for it in (data.get("premises") or data.get("전제") or []):
        st = str(it.get("상태", it.get("status", "")))
        pid = it.get("id", "?")
        if any(x in st for x in ("가정", "미확정", "위반위험")):
            add("전제_미합의", "high" if "위반" in st else "mid",
                f"{pid} 상태={st}", f"{pid}({it.get('진술','')[:30]}) 확정/보류?", "premise.yml")
        # stale: 근거 파일 최종커밋 > 확인시점
        conf = str(it.get("확인시점", ""))[:10]
        for ev in (it.get("근거", []) or []):
            f = (ev.get("파일") if isinstance(ev, dict) else str(ev)).split("#")[0]
            mt = (git_mtime(f) or "")[:10]
            if conf and mt and mt > conf:
                add("전제_stale", "mid", f"{pid} 근거 {f} 갱신({mt})>확인({conf})",
                    f"{pid} 근거 문서 갱신됨 — 전제 재확인?", "premise.yml"); break

# 3) WBS 지연
wbs = load("revision/wbs/wbs.data.json") or (load(".proj-sync/config.json", {}) or {}).get("wbs", {})
today = datetime.date.today().isoformat()
for t in (wbs.get("tasks", []) if isinstance(wbs, dict) else []):
    due = t.get("due")
    if t.get("status") != "완료" and due and str(due) < today and t.get("level") == 3:
        add("WBS_지연", "high", f"{t.get('id')} due={due}", f"지연 task {t.get('id')} 만회/재일정/수용?", "wbs.data.json")

# 4) 요구사항 미매핑
un = load("knowledge/_UNMAPPED.md")
if un:
    n = len(re.findall(r'^- ', un, re.M))
    if n: add("요구사항_미매핑", "mid", f"_UNMAPPED {n}건", f"미매핑 요구사항 {n}건 목차 배치 확정?", "toc.json")

# 5) 평가규정 미확인 (rubric 존재하나 규정 미확정 플래그)
cfg = load(".proj-sync/config.json", {}) or {}
ev = (cfg.get("proposal") or {}).get("eval") or {}
if ev and not ev.get("sw_rule_confirmed"):
    add("평가규정_미확인", "mid", "SW특칙·배점 발주처 확인 필요",
        "가격평가 SW특칙 적용 여부·예정가격 발주처 질의?", "config/질의서")

print(json.dumps(Q, ensure_ascii=False, indent=2))
print(f"\n[hitl_scan] 질문 트리거 {len(Q)}건", file=__import__('sys').stderr)
