#!/usr/bin/env python3
"""proj-sync: 산출물 문서 구조 감사 — 트리분해 기반.

문서를 **헤딩 스택 경로**로 정규화해 문서군 전체를 정량 판정한다.
경로가 diff 키가 되므로, 평면 텍스트 비교로는 안 보이던 것이 드러난다.

  경로 예) "5. 기능별 데이터 보고서 > 5.1 4축분석 > [표1]"

판정 항목
  1. 중복      — 헤딩 경로 Jaccard ≥ 임계값. J=1.00 은 사실상 같은 문서
  2. 구조이상  — H1 부재/복수 · 레벨 건너뜀 · 동일경로 중복 · 장문 단일섹션
  3. 규모      — 헤딩·표·깊이. 비대 문서는 분절 후보
  4. 빈껍데기  — 헤딩만 있고 본문이 거의 없는 문서

형식별 파서 (같은 디렉터리)
  .md            doc_tree_md.py   (마크다운)
  .hwpx / .docx  doc_tree.py      (OOXML, 개요수준·표 파싱)

사용
  doc_audit.py <디렉터리|파일> [--json OUT] [--min-jaccard 0.3]
"""
import sys, os, json, hashlib, importlib.util, collections

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, fname):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, fname))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


_md = _load("doc_tree_md", "doc_tree_md.py")
try:
    _ooxml = _load("doc_tree", "doc_tree.py")
except Exception:
    _ooxml = None

MD_EXT = {".md"}
OOXML_EXT = {".hwpx", ".docx"}


def nodes_of(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in MD_EXT:
        return _md.parse_md(path)
    if ext in OOXML_EXT and _ooxml:
        try:
            return _ooxml.parse(path)
        except Exception:
            return []
    return []


def head_paths(nodes):
    stack, out = [], []
    for kind, lvl, val in nodes:
        if kind != "head":
            continue
        while stack and stack[-1][0] >= lvl:
            stack.pop()
        stack.append((lvl, val))
        out.append(" > ".join(t for _, t in stack))
    return out


def audit(paths, min_jac=0.30):
    docs = {}
    for p in paths:
        nodes = nodes_of(p)
        if not nodes:
            continue
        hp = head_paths(nodes)
        heads = sum(1 for k, _, _ in nodes if k == "head")
        bodys = sum(1 for k, _, _ in nodes if k == "body")
        tables = sum(1 for k, _, _ in nodes if k == "table")
        flaws = _md.structure_flaws(nodes, p) if os.path.splitext(p)[1].lower() in MD_EXT else []
        if heads and bodys / max(heads, 1) < 0.5:
            flaws.append("빈껍데기(헤딩 대비 본문 부족)")
        try:
            sha = hashlib.sha1(open(p, "rb").read()).hexdigest()
        except Exception:
            sha = ""
        docs[p] = {"heads": heads, "bodys": bodys, "tables": tables,
                   "depth": max([l for k, l, _ in nodes if k == "head"] or [0]),
                   "sha1": sha, "head_paths": hp, "flaws": flaws}

    # 바이트 동일 — 가장 강한 중복 신호
    by_sha = collections.defaultdict(list)
    for p, d in docs.items():
        if d["sha1"]:
            by_sha[d["sha1"]].append(p)
    identical = [sorted(v) for v in by_sha.values() if len(v) > 1]

    # 헤딩 경로 겹침
    keys = [k for k in docs if len(set(docs[k]["head_paths"])) >= 4]
    overlaps = []
    for i in range(len(keys)):
        a = set(docs[keys[i]]["head_paths"])
        for j in range(i + 1, len(keys)):
            b = set(docs[keys[j]]["head_paths"])
            inter = a & b
            if not inter:
                continue
            jac = len(inter) / len(a | b)
            if jac >= min_jac:
                overlaps.append({"a": keys[i], "b": keys[j],
                                 "jaccard": round(jac, 3), "shared": len(inter)})
    overlaps.sort(key=lambda x: -x["jaccard"])
    return {"docs": docs, "identical": identical, "overlaps": overlaps}


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    target = sys.argv[1]
    a = sys.argv[2:]
    out = None
    min_jac = 0.30
    for i, x in enumerate(a):
        if x == "--json" and i + 1 < len(a):
            out = a[i + 1]
        if x == "--min-jaccard" and i + 1 < len(a):
            min_jac = float(a[i + 1])

    if os.path.isdir(target):
        files = []
        for r, _, fs in os.walk(target):
            if "/.git" in r:
                continue
            for f in fs:
                if os.path.splitext(f)[1].lower() in (MD_EXT | OOXML_EXT):
                    files.append(os.path.join(r, f))
        files.sort()
    else:
        files = [target]

    rep = audit(files, min_jac)
    docs, ident, ov = rep["docs"], rep["identical"], rep["overlaps"]
    flawed = {p: d["flaws"] for p, d in docs.items() if d["flaws"]}

    print(f"[doc_audit] 문서 {len(docs)}건 · 구조이상 {len(flawed)} · 완전동일 {len(ident)}쌍군 · 겹침 {len(ov)}쌍")
    if ident:
        print("\n■ 완전 동일(바이트 일치) — 정본 1개만 남길 것")
        for g in ident[:20]:
            print("  · " + "  ==  ".join(os.path.relpath(x, target) for x in g))
    if ov:
        print("\n■ 헤딩 경로 겹침 — 통합·상하위화 후보")
        for o in ov[:20]:
            if any(o["a"] in g and o["b"] in g for g in ident):
                continue
            print(f"  J={o['jaccard']:.2f} 공유{o['shared']:3d}  "
                  f"{os.path.relpath(o['a'], target)}  ↔  {os.path.relpath(o['b'], target)}")
    if flawed:
        print("\n■ 구조 이상")
        for p, f in sorted(flawed.items())[:30]:
            print(f"  {os.path.relpath(p, target)[:58]:60} {' · '.join(f)}")
    if out:
        json.dump(rep, open(out, "w"), ensure_ascii=False)
        print(f"\n  → {out}")


if __name__ == "__main__":
    main()
