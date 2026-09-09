#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""전제(Premise) 빌더 — revision/전제/premise.yml(SSOT) → 최상위 PREMISE.md(리뷰 뷰).

revision 축의 **운영시점 사업 전제 레지스터**. WBS/RTM 이 config·json → md·xlsx 인 것과 동형이나,
납품물이 없는 내부 관리 artifact 이므로 최상위 PREMISE.md 하나만 생성한다.

신선도(self-invalidating): 각 전제의 근거 문서가 `확인시점` 이후 git 커밋으로 갱신됐으면
`재확인 필요`(stale)로 자동 표기한다(git log 비교, 결정론적 — manage-schedule 지연탐지와 동류).

경로: env PS_ROOT(프로젝트 루트) 사용(revision_build.sh/premise_build.sh 가 설정). 단독 실행 시 CWD 상위 탐색.
의존성: PyYAML — revision 도구 중 첫 비-stdlib 예외(회의록과 같은 부류). 미설치 시 안내 후 종료.
"""
import os
import subprocess
import sys
from datetime import datetime

try:
    import yaml
except ImportError:
    sys.exit("[build_premise] PyYAML 필요: pip install --user pyyaml")

ICON = {"합의": "🟢", "가정": "🟡", "미확정": "⚪", "위반위험": "🔴"}
STATUS_ORDER = ["합의", "가정", "미확정", "위반위험"]


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
    sys.exit("[build_premise] .proj-sync/config.json 를 찾지 못함 (PS_ROOT 미설정)")


def git_last_commit(root, path_rel):
    """근거 파일의 마지막 커밋 시각(local naive datetime). 미추적/오류면 None."""
    try:
        r = subprocess.run(
            ["git", "log", "-1", "--format=%cd",
             "--date=format-local:%Y-%m-%dT%H:%M:%S", "--", path_rel],
            cwd=root, capture_output=True, text=True, timeout=10,
        )
        s = r.stdout.strip()
        return datetime.fromisoformat(s) if s else None
    except Exception:
        return None


def parse_when(s):
    s = str(s or "").strip()
    try:
        return datetime.fromisoformat(s if "T" in s else s + "T00:00:00")
    except Exception:
        return None


def freshness(root, p):
    """근거 파일 중 하나라도 확인시점 이후 갱신 → 재확인 필요."""
    when = parse_when(p.get("확인시점"))
    stale = []
    for g in p.get("근거", []) or []:
        fpath = str(g.get("위치", "")).split("#", 1)[0]      # 앵커 제거 → 파일 경로
        if not fpath:
            continue
        ts = git_last_commit(root, fpath)
        if ts is not None and when is not None and ts > when:
            stale.append((fpath, ts))
    return ("재확인 필요" if stale else "최신"), stale


def src_tag(g):
    rev = g.get("rev", "")
    return f"{g.get('유형', '')}@{rev}" if rev else str(g.get("유형", ""))


def as_list(v):
    if isinstance(v, list):
        return [str(x) for x in v]
    return [str(v)] if v else []


def main():
    root = _find_root()
    src = os.path.join(root, "revision", "전제", "premise.yml")
    out = os.path.join(root, "PREMISE.md")
    if not os.path.isfile(src):
        sys.exit("[build_premise] SSOT 없음: revision/전제/premise.yml (/ax:premise·manage-premise 로 생성)")
    with open(src, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    meta = data.get("meta", {}) or {}
    items = data.get("전제", []) or []

    cnt_status, cnt_fresh, stale_all, rows = {}, {"최신": 0, "재확인 필요": 0}, [], []
    for p in items:
        st = p.get("상태", "미확정")
        cnt_status[st] = cnt_status.get(st, 0) + 1
        fresh, stale = freshness(root, p)
        cnt_fresh[fresh] += 1
        if stale:
            stale_all.append((p, stale))
        rows.append((p, st, fresh))

    now = datetime.now().strftime("%Y-%m-%d")
    stat = " · ".join(f"{ICON.get(k, '')}{k} {cnt_status[k]}"
                      for k in STATUS_ORDER if cnt_status.get(k)) or "(없음)"

    L = []
    L.append("# PREMISE — 사업 전제 레지스터\n")
    L.append("> **운영시점(run-time) 사업 전제.** "
             "revision(history·WBS·요구사항추적표·회의록)을 증류한 **살아있는 레지스터**.  ")
    L.append("> ⚠️ 이 파일은 **파생물** — SSOT는 `revision/전제/premise.yml`. "
             "손대지 말고 yml 을 고쳐 `/ax:premise` 재빌드.  ")
    L.append(f"> 생성 {now} · 전제 {len(items)}건 · 갱신주기 {meta.get('갱신주기', '주간')}\n")

    L.append("## 요약")
    L.append(f"- **상태**: {stat}")
    L.append(f"- **신선도**: ✅ 최신 {cnt_fresh['최신']} · ⚠️ 재확인 필요 {cnt_fresh['재확인 필요']}\n")

    if stale_all:
        L.append("## ⚠️ 재확인 필요 (근거 문서가 확인시점 이후 갱신됨)")
        for p, stale in stale_all:
            s = ", ".join(f"`{fp}`(갱신 {ts.strftime('%Y-%m-%d')})" for fp, ts in stale)
            L.append(f"- **{p.get('id', '')} {p.get('유형', '')}** — 확인 {p.get('확인시점', '')} 이후 갱신: {s}")
        L.append("")

    if items:
        L.append("## 전제 목록")
        L.append("| id | 유형 | 진술 | 출처 | 상태 | 신선도 | 흔들리면 파급 | 후속조치 |")
        L.append("|----|------|------|------|------|--------|--------------|----------|")
        for p, st, fresh in rows:
            srcs = "<br>".join(src_tag(g) for g in p.get("근거", []) or [])
            pag = "<br>".join(as_list(p.get("파급")))
            fresh_mark = "✅ 최신" if fresh == "최신" else "⚠️ 재확인"
            L.append(f"| {p.get('id', '')} | {p.get('유형', '')} | {p.get('진술', '')} | {srcs} | "
                     f"{ICON.get(st, '')}{st} | {fresh_mark} | {pag} | {p.get('후속', '') or ''} |")
        L.append("")
        L.append("## 근거 (provenance) — 역추적")
        for p in items:
            L.append(f"- **{p.get('id', '')}** ({p.get('상태', '')} · 확인 {p.get('확인시점', '')})")
            for g in p.get("근거", []) or []:
                L.append(f"  - `{g.get('위치', '')}` — 출처유형 **{g.get('유형', '')}** · 인용 rev {g.get('rev', '')}")
        L.append("")
    else:
        L.append("_아직 전제가 없습니다. `revision/전제/premise.yml` 에 전제를 추가하고 재빌드하세요._\n")

    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(L))
    print(f"[premise] {len(items)}건 → PREMISE.md "
          f"(상태: {stat} / 신선도: 최신 {cnt_fresh['최신']}·재확인 {cnt_fresh['재확인 필요']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
