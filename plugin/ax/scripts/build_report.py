#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""주간보고(Weekly Report) 빌더 — revision 축을 증류한 **발신면(發信面)**.

revision(전제·config.wbs·요구사항추적표·history) + 표준 산출물 마스터를 읽어 주간보고 md 를
`reference/management/reports/주간보고_{YYYYMMDD}.md` 로 **결정론 생성**한다. (DESIGN §H)

  맨 위 **📮 Slack 발신본**(PM 이 slack_post.sh 로 게시할 요약, 리스크 먼저·담당 지목)
  이어 5섹션: ① 리스크 ② 진척·일정 ③ 금주실적·차주계획 ④ 결정 필요 ⑤ 산출물 현황·누락

이 md 는 "사실(facts) 스켈레톤" — manage-report 스킬에서 PM 이 서술을 얹고 slack_post.sh 로 발신한다.
즉 **사실(build_report) ⊥ 서술(PM) ⊥ 발신(slack)** (DESIGN §H·ARCHITECTURE A3). 자체 SSOT 없음(revision 파생).

입력:  config.wbs(status·due·milestones) · revision/전제/premise.yml · revision/요구사항추적표/rtm.data.json
       · revision/history.md · templates/deliverables.json(profile별 별표2)
신선도(전제 stale): 근거가 확인시점 이후 git 갱신됐으면 리스크로 표기(build_premise.py 와 동형).
경로:  env PS_ROOT(프로젝트 루트)·PS_CONFIG 사용(report_build.sh 설정). 단독 실행 시 CWD 상위 탐색.
날짜:  기본 date.today(). PROJ_SYNC_REPORT_DATE=YYYY-MM-DD 로 고정(예시·테스트 재현).
의존성: PyYAML(premise.yml) — 회의록·전제에 이은 tools stdlib 3번째 예외.

사용: python3 scripts/build_report.py   (보통 report_build.sh / /ax:report 가 호출)
"""
import json
import os
import re
import subprocess
import sys
from datetime import date, datetime, timedelta

# PyYAML 은 premise.yml 에만 필요하다. 모듈 로드 시점에 죽이면 --digest(세션 훅)까지 같이
# 죽는다 — 훅은 어떤 실패에도 세션을 막지 않아야 한다. 여기서는 없으면 None 으로 두고,
# **실제로 필요한 곳**에서 판정한다(주간보고는 종전대로 즉시 중단).
try:
    import yaml
except ImportError:
    yaml = None

HERE = os.path.dirname(os.path.abspath(__file__))
DELIV_MASTER = os.path.join(os.path.dirname(HERE), "templates", "deliverables.json")

PICON = {"합의": "🟢", "가정": "🟡", "미확정": "⚪", "위반위험": "🔴"}
DONE = "완료"
STATUS_ORDER = ["미착수", "진행중", "검토중", "완료"]
# phase 정합성(§0.5, agents/pm.md) — 이 phase 는 해당 stage 산출물이 1건 이상 있어야 "실제 진행 중".
PHASE_STAGE = {"수행중": "착수", "완료": "종료"}


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
    sys.exit("[build_report] .proj-sync/config.json 를 찾지 못함 (PS_ROOT 미설정 · /ax:init 필요)")


# ── 날짜·git 헬퍼 ─────────────────────────────────────────────────
def report_date():
    s = os.environ.get("PROJ_SYNC_REPORT_DATE", "").strip()
    return date.fromisoformat(s) if s else date.today()


def parse_date(s):
    m = re.search(r"(\d{4})-(\d{2})-(\d{2})", str(s or ""))
    return date(int(m[1]), int(m[2]), int(m[3])) if m else None


def git_last_commit(root, path_rel):
    """근거 파일의 마지막 커밋 시각(local naive datetime). 미추적/오류면 None. (build_premise.py 동형)"""
    try:
        r = subprocess.run(
            ["git", "log", "-1", "--format=%cd",
             "--date=format-local:%Y-%m-%dT%H:%M:%S", "--", path_rel],
            cwd=root, capture_output=True, text=True, timeout=10)
        s = r.stdout.strip()
        return datetime.fromisoformat(s) if s else None
    except Exception:
        return None


def premise_stale(root, p):
    when = parse_date(p.get("확인시점"))
    when_dt = datetime(when.year, when.month, when.day) if when else None
    for g in p.get("근거", []) or []:
        fpath = str(g.get("위치", "")).split("#", 1)[0]
        if not fpath:
            continue
        ts = git_last_commit(root, fpath)
        if ts is not None and when_dt is not None and ts > when_dt:
            return True
    return False


def task_due(t, base):
    d = parse_date(t.get("due"))
    if d:
        return d
    if base is not None and t.get("end_w") is not None:
        return base + timedelta(days=int(t["end_w"]) * 7 - 1)
    return None


def _load_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, ValueError):
        return default


# ── 산출물 마스터(별표2) — §5 ─────────────────────────────────────
def deliverable_status(root, profile, phase):
    """templates/deliverables.json 로 profile 산출물 완료/미착수 + 현 phase 착수 누락.
    반환: (total, done_n, todo, phase_stage, phase_missing, ok)."""
    master = _load_json(DELIV_MASTER, {})
    keys = (master.get("profiles", {}) or {}).get(profile, []) or []
    stage_dirs = master.get("stage_dirs", {}) or {}
    delivs = master.get("deliverables", {}) or {}
    done_n, todo = 0, []
    exists = {}   # stage → set(작성된 name)
    for k in keys:
        d = delivs.get(k, {})
        name, stage = d.get("name"), d.get("stage")
        sd = stage_dirs.get(stage, "")
        path = os.path.join(root, "reference", sd, f"{name}.md") if sd and name else ""
        if path and os.path.isfile(path):
            done_n += 1
            exists.setdefault(stage, set()).add(name)
        else:
            todo.append((name, stage))
    # phase 정합성(§0.5): 수행중→착수 최소바(그 stage 산출물 0 이면 경고)
    ps = PHASE_STAGE.get(phase)
    phase_missing, ok = [], True
    if ps:
        want = [delivs[k]["name"] for k in keys if delivs.get(k, {}).get("stage") == ps]
        have = exists.get(ps, set())
        phase_missing = [nm for nm in want if nm not in have]
        ok = bool(have) if want else True
    return len(keys), done_n, todo, ps, phase_missing, ok


# ── history 헬퍼 (축약) ───────────────────────────────────────────
def _bullet_title(line):
    m = re.search(r"\*\*(.+?)\*\*", line)
    if m:
        return m.group(1).strip()
    t = line.lstrip("-*○ ").strip()
    return (t[:34] + "…") if len(t) > 34 else t


def recent_history(hist_path, today, days=7):
    if not os.path.isfile(hist_path):
        return []
    txt = open(hist_path, encoding="utf-8").read()
    parts = re.split(r"\n## (\d{4}-\d{2}-\d{2})\s*\n", txt)
    out = []
    for i in range(1, len(parts), 2):
        d = parse_date(parts[i])
        body = parts[i + 1] if i + 1 < len(parts) else ""
        if d and d <= today and (today - d).days <= days:
            # 이 저장소군은 `○ **제목**` 을 항목, `- …` 을 그 세부로 쓴다(기관C·기관D).
            # 세부만 뽑으면 "발신 경로: …" 같은 조각이 제목 자리에 온다 — 항목이 있으면 항목을 쓴다.
            # `○` 를 안 쓰는 나머지 19개 사업은 종전과 동일하게 `- ` 로 떨어진다.
            # 취소선(`~~…~~`)은 이 저장소군에서 **철회·해결됨** 표기다(기관C history.md:25).
            # 그어진 줄을 금주 실적으로 올리면 사실과 다르다 — 뺀다.
            lines = [ln for ln in body.splitlines() if "~~" not in ln]
            heads = [ln for ln in lines if ln.startswith("○ ")]
            src = heads or [ln for ln in lines if ln.startswith("- ")]
            titles = [t for t in (_bullet_title(ln) for ln in src) if t]
            out.append((d, titles))
    return sorted(out, reverse=True)


def prev_completion(outdir, today):
    """직전(날짜<today) 주간보고 md 에서 완료율 파싱 → (date, rate) or None. 추이(momentum)용."""
    best = None
    try:
        files = os.listdir(outdir)
    except FileNotFoundError:
        return None
    for fn in files:
        m = re.match(r"주간보고_(\d{8})\.md$", fn)
        if not m:
            continue
        d = datetime.strptime(m.group(1), "%Y%m%d").date()
        if d < today and (best is None or d > best[0]):
            txt = open(os.path.join(outdir, fn), encoding="utf-8").read()
            mm = re.search(r"완료율\s*([\d.]+)%", txt)
            if mm:
                best = (d, float(mm.group(1)))
    return best


# ── 본체 ─────────────────────────────────────────────────────────
def load_premises(root):
    """revision/전제/premise.yml → 전제 리스트. PyYAML 이 없으면 빈 리스트(호출부가 판단)."""
    p = os.path.join(root, "revision", "전제", "premise.yml")
    if yaml is None or not os.path.isfile(p):
        return []
    with open(p, encoding="utf-8") as f:
        return (yaml.safe_load(f) or {}).get("전제", []) or []


def facts(root, conf, today):
    """주간보고와 세션 digest 가 **같은 판정**을 쓰도록 공유하는 사실 계산.

    두 벌로 두면 지연·stale 기준이 갈려 **주간보고와 세션 요약이 서로 다른 말을 한다.**
    새 소비자가 생기면 여기에 붙이고, 판정식을 복제하지 않는다.
    """
    wbs = conf.get("wbs", {}) or {}
    base = parse_date(wbs.get("base_date"))
    leaves = [t for t in wbs.get("tasks", []) if t.get("level") == 3]
    milestones = wbs.get("milestones", []) or []

    n = ((today - base).days // 7 + 1) if base else None
    total_w = max((int(m["week"]) for m in milestones), default=None)

    cnt = {s: 0 for s in STATUS_ORDER}
    for t in leaves:
        cnt[t.get("status", "미착수")] = cnt.get(t.get("status", "미착수"), 0) + 1
    done_n = cnt.get(DONE, 0)

    delayed, soon = [], []
    for t in leaves:
        if t.get("status") == DONE:
            continue
        due = task_due(t, base)
        if not due:
            continue
        if due < today:
            delayed.append((t, due, (today - due).days))
        elif due <= today + timedelta(days=7):
            soon.append((t, due, (due - today).days))
    delayed.sort(key=lambda x: -x[2])
    soon.sort(key=lambda x: x[2])

    ms_rows = [(m, base + timedelta(days=int(m["week"]) * 7 - 1),
                (base + timedelta(days=int(m["week"]) * 7 - 1) - today).days)
               for m in milestones] if base else []

    premises = load_premises(root)
    return {
        "base": base, "leaves": leaves, "milestones": milestones,
        "cnt": cnt, "done_n": done_n,
        "rate": (done_n / len(leaves) * 100) if leaves else 0.0,
        "delayed": delayed, "soon": soon,
        "ms_rows": ms_rows,
        "nextms": min((r for r in ms_rows if r[2] >= 0), key=lambda x: x[2], default=None),
        "n": n, "total_w": total_w,
        "hdr_w": (f"W{n}/{total_w}" if n and total_w else (f"W{n}" if n else "")),
        "premises": premises,
        "viol": [p for p in premises if p.get("상태") == "위반위험"],
        "stale": [p for p in premises if premise_stale(root, p)],
    }


# ── --digest: 세션 시작 훅이 주입할 압축 맥락 ─────────────────────
# 주간보고와 **같은 facts()** 를 쓴다. 판정이 갈리면 둘이 서로 다른 말을 한다.
DIGEST_CAP = 4000          # 매 세션 컨텍스트에 실린다 — 길수록 모델이 덜 읽는다


def _git(root, *args):
    try:
        r = subprocess.run(["git", *args], cwd=root, capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def open_items(hist_path, limit=5):
    """history.md 에서 아직 **열린** 항목만.

    이 저장소의 관습: `⚠` 로 미해결을 적고, 해결되면 줄을 지우지 않고 **취소선(`~~…~~`)**을 긋는다
    (기관C `revision/history.md:25` 가 그 형태). 취소선이 있으면 닫힌 것이므로 제외한다 —
    닫힌 항목을 미해결로 주입하면 매 세션 이미 끝난 일을 다시 꺼내게 된다.
    """
    if not os.path.isfile(hist_path):
        return []
    out = []
    for ln in open(hist_path, encoding="utf-8"):
        s = ln.strip()
        if "⚠" not in s or "~~" in s:
            continue
        s = re.sub(r"[*`○⚠]", "", s).strip(" -·—")
        if s:
            out.append((s[:110] + "…") if len(s) > 110 else s)
    return out[:limit]


def digest():
    """압축 맥락을 stdout 으로. 말할 게 없으면 **아무것도 출력하지 않는다**(훅이 침묵).

    어떤 상황에서도 0 을 반환한다 — 세션 시작을 막지 않는 것이 첫 번째 제약이다.
    """
    try:
        root = _find_root()          # .proj-sync 없는 곳(예: 우산 저장소)에서는 SystemExit
    except SystemExit:
        return 0
    try:
        conf = _load_json(os.environ.get("PS_CONFIG")
                          or os.path.join(root, ".proj-sync", "config.json"), {})
        today = report_date()
        F = facts(root, conf, today)

        proj = (conf.get("project", {}) or {}).get("name") or os.path.basename(root)
        phase = (conf.get("lifecycle", {}) or {}).get("phase", "")
        branch = _git(root, "rev-parse", "--abbrev-ref", "HEAD")

        L = [f"── {proj}" + (f" · phase={phase}" if phase else "")
             + (f" · {F['hdr_w']}" if F["hdr_w"] else "")
             + (f" · branch {branch}" if branch else "")]

        if yaml is None:
            L.append("[전제] PyYAML 미설치로 생략")
        elif F["viol"] or F["stale"]:
            bits = []
            if F["viol"]:
                bits.append("위반위험 " + ", ".join(str(p.get("id") or p.get("제목", "")) for p in F["viol"][:3]))
            if F["stale"]:
                bits.append("재확인 필요 " + ", ".join(str(p.get("id") or p.get("제목", "")) for p in F["stale"][:3]))
            L.append("[전제] " + " · ".join(bits))

        if F["delayed"] or F["soon"] or F["nextms"]:
            bits = []
            if F["delayed"]:
                bits.append(f"지연 {len(F['delayed'])} (" +
                            ", ".join(f"{t['wbs']} {d}일" for t, _, d in F["delayed"][:3]) + ")")
            if F["soon"]:
                bits.append(f"마감임박 {len(F['soon'])}")
            if F["nextms"]:
                m, _due, dleft = F["nextms"]
                bits.append(f"다음 마일스톤 {m.get('name', m.get('id', ''))} D-{dleft}")
            L.append("[일정] " + " · ".join(bits) + f" · 완료율 {F['rate']:.0f}%")

        hist_path = os.path.join(root, "revision", "history.md")
        for d, titles in recent_history(hist_path, today, days=30)[:2]:
            L.append(f"[revision {d.isoformat()}] " + " / ".join(titles[:5]))

        items = open_items(hist_path)
        if items:
            L.append(f"[미해결 {len(items)}건]")
            L += [f"  ⚠ {s}" for s in items]

        log = _git(root, "log", "-5", "--format=%h|%an|%s")
        if log:
            rows = []
            for ln in log.splitlines():
                p = ln.split("|", 2)
                if len(p) == 3:
                    s = p[2][:46] + ("…" if len(p[2]) > 46 else "")
                    rows.append(f"{p[0]} {p[1]} {s}")
            if rows:
                L.append("[최근 커밋]")
                L += [f"  {r}" for r in rows]

        if len(L) <= 1:              # 머리글만 남았다 = 말할 게 없다
            return 0
        out = "\n".join(L)
        if len(out) > DIGEST_CAP:
            out = out[:DIGEST_CAP] + "\n…(생략)"
        sys.stdout.buffer.write(out.encode("utf-8"))
    except Exception:
        return 0                     # 진단 목적이 아니다 — 조용히 물러난다
    return 0


def main():
    if "--digest" in sys.argv:
        return digest()
    if yaml is None:
        sys.exit("[build_report] PyYAML 필요: pip install --user pyyaml")
    root = _find_root()
    cfg_path = os.environ.get("PS_CONFIG") or os.path.join(root, ".proj-sync", "config.json")
    conf = _load_json(cfg_path, {})
    wbs = conf.get("wbs", {}) or {}
    outdir = os.path.join(root, "reference", "management", "reports")

    today = report_date()
    profile = wbs.get("profile", "")
    phase = (conf.get("lifecycle", {}) or {}).get("phase", "")
    proj = (conf.get("project", {}) or {}).get("name") or "사업"

    F = facts(root, conf, today)
    base, leaves, milestones = F["base"], F["leaves"], F["milestones"]
    cnt, done_n, rate = F["cnt"], F["done_n"], F["rate"]
    delayed, soon = F["delayed"], F["soon"]
    ms_rows, nextms, hdr_w, n = F["ms_rows"], F["nextms"], F["hdr_w"], F["n"]
    premises, viol, stale = F["premises"], F["viol"], F["stale"]

    rdata = _load_json(os.path.join(root, "revision", "요구사항추적표", "rtm.data.json"), {})
    reqs = rdata.get("requirements", []) or []
    hist_path = os.path.join(root, "revision", "history.md")

    d_total, d_done, d_todo, ph_stage, ph_missing, ph_ok = deliverable_status(root, profile, phase)

    # 결정
    undecided = [p for p in premises if p.get("상태") == "미확정"]
    followups = [(p, p.get("후속")) for p in premises if p.get("상태") != "합의" and p.get("후속")]
    rtm_decide = [r for r in reqs if re.search(r"협의\s*필요|확정\s*필요", str(r.get("plan", "")))]

    # 산출물(RTM)
    lvl = {}
    for r in reqs:
        L = str(r.get("level", "")).split("(")[0].strip()
        if L:
            lvl[L] = lvl.get(L, 0) + 1
    weak = [r for r in reqs if str(r.get("level", "")).startswith("미흡")]

    n_risk = len(delayed) + len(viol) + len(stale) + (0 if ph_ok else 1)
    n_dec = len(undecided) + len(rtm_decide)

    prev = prev_completion(outdir, today)
    delta_str = ""
    if prev:
        dp = rate - prev[1]
        arrow = "▲" if dp > 0.05 else ("▼" if dp < -0.05 else "→")
        delta_str = f" (지난주 {prev[1]:.1f}% {arrow}{abs(dp):.1f}p)"
    resp = {}
    for t, _, _ in delayed:
        resp.setdefault(t.get("owner") or t.get("team") or "⚠️미할당", []).append(f"{t['wbs']} 지연")
    for t, _, _ in soon:
        resp.setdefault(t.get("owner") or t.get("team") or "⚠️미할당", []).append(f"{t['wbs']} 임박")
    resp_line = " · ".join(f"{who}({', '.join(v)})" for who, v in resp.items()) or "-"

    # ══ 마크다운 ══
    L = []
    L.append(f"# 주간보고 — {proj}")
    L.append(f"> {today.isoformat()} · {hdr_w} · 🔴 리스크 {n_risk}신호 · 🟡 결정대기 {n_dec}건 · "
             f"📊 완료율 {rate:.1f}%{delta_str}  ")
    L.append("> ⚠️ **파생물** — SSOT 없음(revision/config 증류). manage-report 스킬에서 PM 이 아래 "
             "**📮 Slack 발신본**에 한 줄 총평을 얹어 채널 게시. 재빌드: `/ax:report`. (DESIGN §H)\n")

    risk_bits = []
    if not ph_ok:
        risk_bits.append(f"{ph_stage}산출물 0건")
    if delayed:
        risk_bits.append("일정위험 " + ",".join(f"{t['wbs']}(+{dd}일)" for t, _, dd in delayed[:2]))
    if viol:
        risk_bits.append(f"위반위험 전제 {len(viol)}")
    if stale:
        risk_bits.append(f"재확인필요 {len(stale)}")
    dec_bits = []
    if undecided:
        dec_bits.append(f"미확정 {len(undecided)}({undecided[0].get('id')})")
    if followups:
        dec_bits.append(f"후속 {len(followups)}")
    if rtm_decide:
        dec_bits.append(f"RTM협의 {len(rtm_decide)}")
    prod = f"RTM 미흡 {len(weak)}" + (f" · {ph_stage}산출물 누락 {len(ph_missing)}" if ph_missing else "")
    ms_txt = f"다음 {nextms[0]['id']} {nextms[0]['name']} D-{nextms[2]}" if nextms else "-"
    rel = os.path.relpath(os.path.join(outdir, f"주간보고_{today.strftime('%Y%m%d')}.md"), root)

    L.append("```text")
    L.append("📮 Slack 발신본  (manage-report: slack_post.sh 가 config.slack.channel_id 로 게시)")
    L.append(f"📋 주간보고 · {proj} · {hdr_w} · {today.isoformat()}")
    L.append(f"📊 완료율 {rate:.1f}%({done_n}/{len(leaves)}){delta_str} · 지연 {len(delayed)} · 마감임박 {len(soon)} · {ms_txt}")
    L.append(f"🔴 리스크 {n_risk}: " + (" · ".join(risk_bits) or "특이 없음"))
    L.append(f"🟡 결정 {n_dec}: " + (" · ".join(dec_bits) or "없음"))
    L.append(f"📦 산출물: {prod}")
    L.append(f"👤 담당: {resp_line}")
    L.append(f"🔗 상세 {rel}   (owner→config.mentions 멘션)")
    L.append("```\n")

    # 🔴 1. 리스크
    L.append("## 🔴 1. 리스크")
    if not ph_ok:
        L.append(f"- **산출물 진척 위험** — ⚠️ 명목 phase=`{phase}` 이나 **{ph_stage} 산출물 0건**(실제 진척은 {ph_stage} 단계)")
        if ph_missing:
            L.append(f"  - 미작성 {ph_stage} 산출물: {', '.join(ph_missing)}")
    if delayed:
        L.append(f"- **일정 위험** — 지연 {len(delayed)}건 (status≠완료 AND due<오늘):")
        for t, due, dd in delayed[:5]:
            L.append(f"  - `{t['wbs']}` {t.get('name','')} — 마감 {due.isoformat()} 초과 **{dd}일** ({t.get('owner') or t.get('team','')})")
    if viol:
        L.append("- **위반위험 전제**:")
        for p in viol:
            L.append(f"  - 🔴 `{p.get('id')}` {p.get('진술','')} → 후속: {p.get('후속','')}")
    if stale:
        L.append("- **재확인 필요(stale) 전제** — 근거가 확인시점 이후 갱신됨:")
        for p in stale:
            L.append(f"  - ⚠️ `{p.get('id')}` {p.get('유형','')}: {p.get('진술','')} (확인 {p.get('확인시점','')})")
    if ph_ok and not (delayed or viol or stale):
        L.append("- 활성 리스크 없음")
    L.append("")

    # 📊 2. 진척·일정
    L.append("## 📊 2. 진척·일정")
    if leaves:
        L.append(f"- **완료율 {rate:.1f}%**{delta_str} — " + " · ".join(
            f"{s} {cnt.get(s,0)}" for s in STATUS_ORDER) + f" (leaf {len(leaves)})")
    else:
        L.append("- WBS 미정의 (`config.wbs.tasks` — /ax:revision)")
    if soon:
        L.append(f"- **마감 임박 {len(soon)}건** (7일 이내): "
                 + " · ".join(f"`{t['wbs']}` D-{dd}" for t, _, dd in soon[:5]))
    if ms_rows:
        L.append("- **마일스톤**: " + " · ".join(
            f"{m['id']} {m['name']}(W{m['week']}) " + (f"D-{dd}" if dd >= 0 else f"D+{-dd}")
            for m, _, dd in ms_rows))
    L.append("")

    # ✅ 3. 금주 실적 · 차주 계획
    L.append("## ✅ 3. 금주 실적 · 차주 계획")
    hist = recent_history(hist_path, today, 7)
    if hist:
        L.append("**금주 실적** (history 지난 7일 · 핵심):")
        for d, titles in hist:
            L.append(f"- {d.isoformat()}: " + " · ".join(titles[:6]))
    else:
        L.append("**금주 실적**: history 기록 없음 (revision/history.md 갱신 필요)")
    if n:
        nextw = [t for t in leaves if t.get("start_w") and t.get("end_w")
                 and int(t["start_w"]) <= n + 1 <= int(t["end_w"]) and t.get("status") != DONE]
        L.append(f"\n**차주 계획 (W{n+1})** — 진행 예정 {len(nextw)}건:")
        for t in nextw[:8]:
            L.append(f"- `{t['wbs']}` {t.get('name','')} ({t.get('owner') or t.get('team','')}, W{t['start_w']}-{t['end_w']})")
    L.append("")

    # 🟡 4. 결정 필요
    L.append("## 🟡 4. 결정 필요")
    if undecided:
        L.append("- **미확정 전제** (확정 주체·시점 필요):")
        for p in undecided:
            L.append(f"  - ⚪ `{p.get('id')}` {p.get('유형','')}: {p.get('진술','')} → **{p.get('후속','')}**")
    if followups:
        L.append("- **후속조치 대기** (상태≠합의):")
        for p, fu in followups:
            L.append(f"  - `{p.get('id')}` {PICON.get(p.get('상태'),'')}{p.get('상태','')}: {fu}")
    if rtm_decide:
        L.append("- **요구사항 협의/확정 필요**:")
        for r in rtm_decide[:5]:
            L.append(f"  - `{r.get('id')}` {r.get('text','')} — 대응방안 확정 필요")
    if not (undecided or followups or rtm_decide):
        L.append("- 대기 중 결정사항 없음")
    L.append("")

    # 📦 5. 산출물 현황·누락
    denom = sum(v for k, v in lvl.items() if not k.startswith("해당없음"))
    L.append("## 📦 5. 산출물 현황·누락")
    if d_total:
        L.append(f"- **별표2({profile})**: {d_total}개 중 완료 {d_done} · 미착수 {d_total - d_done}"
                 + (f" · **{ph_stage} 누락 {len(ph_missing)}건**: {', '.join(ph_missing)}" if ph_missing else ""))
    if reqs:
        L.append(f"- **요구사항 충족도** (RTM {len(reqs)}건, '해당없음' 제외 {denom}): "
                 + " · ".join(f"{k} {v}" for k, v in sorted(lvl.items())))
        if weak:
            L.append(f"- **미흡 {len(weak)}건** (보완 필요):")
            for r in weak:
                L.append(f"  - `{r.get('id')}` {r.get('text','')}")
    else:
        L.append("- 요구사항추적표 미정의 (`revision/요구사항추적표/rtm.data.json` — /ax:revision)")
    L.append("")

    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, f"주간보고_{today.strftime('%Y%m%d')}.md")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(L))
    print(f"[주간보고] {today.isoformat()} {hdr_w} → {os.path.relpath(out, root)} "
          f"(리스크 {n_risk} · 완료율 {rate:.1f}% · 지연 {len(delayed)} · 결정 {n_dec} · 미흡 {len(weak)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
