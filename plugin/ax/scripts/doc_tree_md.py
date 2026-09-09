#!/usr/bin/env python3
"""문서 트리구조 분해 파서 — 마크다운·Notion 확장판.

proj-gamma/scripts/doc_tree.py (hwpx·docx 전용, 2026-07-28) 의 기법을
마크다운 문서군과 Notion 문서함 트리에 적용한다. 핵심 아이디어는 동일하다:

  **헤딩 스택으로 노드 경로를 만들어 diff 키로 쓴다.**
  예) "5. 기능별 데이터 보고서 > 5.1 4축분석 > [표1]"

원본과 다른 점
- 입력이 OOXML 이 아니라 마크다운(ATX/Setext 헤딩)·Notion relation 트리다.
- 단일 문서 분해에 그치지 않고 **문서군 전체를 경로 집합으로 정규화**해
  중복·구조이상·고아를 정량 판정한다(문서 체계 최적화가 목적).

출력
  --paths OUT.tsv   노드 경로 리스트 (원본 doc_tree.py 와 같은 계약)
  --report OUT.json 문서군 분석 — 구조이상·경로중복·규모
  기본은 요약을 stdout 으로.

사용
  python3 scripts/doc_tree_md.py docs/               # 디렉터리 일괄
  python3 scripts/doc_tree_md.py docs/A.md --paths out.tsv
"""
import sys, os, re, json, hashlib, collections

# 코드블록·표는 헤딩 판정에서 제외해야 오탐이 없다.
FENCE = re.compile(r'^\s*(```|~~~)')
ATX = re.compile(r'^(#{1,6})\s+(.*?)\s*#*\s*$')
SETEXT = re.compile(r'^\s*(=+|-+)\s*$')


def _clean(s):
    return re.sub(r'\s+', ' ', (s or '')).strip()


def parse_md(path):
    """(kind, level, value) 노드 리스트. kind: head|body|table"""
    try:
        lines = open(path, encoding='utf-8', errors='replace').read().splitlines()
    except Exception:
        return []
    nodes, in_fence, prev = [], False, None
    tbl = []
    for ln in lines:
        if FENCE.match(ln):
            in_fence = not in_fence
            if prev is not None:
                nodes.append(('body', None, prev)); prev = None
            continue
        if in_fence:
            continue
        # 표 누적 (GFM)
        if ln.strip().startswith('|') and ln.strip().endswith('|'):
            cells = [_clean(c) for c in ln.strip().strip('|').split('|')]
            if not all(re.fullmatch(r':?-{2,}:?', c or '') for c in cells):
                tbl.append(cells)
            continue
        if tbl:
            nodes.append(('table', None, tbl)); tbl = []
        m = ATX.match(ln)
        if m:
            if prev is not None:
                nodes.append(('body', None, prev)); prev = None
            nodes.append(('head', len(m.group(1)), _clean(m.group(2))))
            continue
        if SETEXT.match(ln) and prev:
            lvl = 1 if ln.strip().startswith('=') else 2
            nodes.append(('head', lvl, _clean(prev))); prev = None
            continue
        if prev is not None:
            nodes.append(('body', None, prev))
        prev = _clean(ln) or None
    if prev is not None:
        nodes.append(('body', None, prev))
    if tbl:
        nodes.append(('table', None, tbl))
    return nodes


def to_paths(nodes):
    """헤딩 스택 → 경로. 원본 doc_tree.py to_paths 와 같은 형식."""
    stack, lines = [], []
    tcount = bcount = 0
    for kind, lvl, val in nodes:
        if kind == 'head':
            while stack and stack[-1][0] >= lvl:
                stack.pop()
            stack.append((lvl, val))
            lines.append(' > '.join(t for _, t in stack) + '\tHEAD')
            bcount = tcount = 0
        else:
            path = ' > '.join(t for _, t in stack) or '(root)'
            if kind == 'table':
                tcount += 1
                flat = ' / '.join(' '.join(r) for r in val)
                lines.append(f'{path} > [표{tcount}]\t{flat[:200]}')
            else:
                bcount += 1
                lines.append(f'{path} > b{bcount}\t{val[:200]}')
    return '\n'.join(lines)


def head_paths(nodes):
    """헤딩 경로만 집합으로 — 문서 간 대조 키."""
    stack, out = [], []
    for kind, lvl, val in nodes:
        if kind != 'head':
            continue
        while stack and stack[-1][0] >= lvl:
            stack.pop()
        stack.append((lvl, val))
        out.append(' > '.join(t for _, t in stack))
    return out


def structure_flaws(nodes, path):
    """계층 규칙 위반 — 체계화의 판정 근거."""
    flaws = []
    heads = [(l, v) for k, l, v in nodes if k == 'head']
    if not heads:
        flaws.append('헤딩 없음(평문)')
        return flaws
    h1 = [v for l, v in heads if l == 1]
    if len(h1) == 0:
        flaws.append('H1 없음(문서 제목 부재)')
    elif len(h1) > 1:
        flaws.append(f'H1 {len(h1)}개(단일 제목 규칙 위반)')
    prev = None
    jumps = 0
    for l, v in heads:
        if prev is not None and l > prev + 1:
            jumps += 1
        prev = l
    if jumps:
        flaws.append(f'레벨 건너뜀 {jumps}회')
    dup = [k for k, c in collections.Counter(head_paths(nodes)).items() if c > 1]
    if dup:
        flaws.append(f'동일 경로 중복 {len(dup)}건')
    if len(heads) == 1 and sum(1 for k, _, _ in nodes if k == 'body') > 120:
        flaws.append('장문 단일섹션(분절 필요)')
    return flaws


def analyze(paths):
    docs = {}
    for p in paths:
        nodes = parse_md(p)
        hp = head_paths(nodes)
        docs[p] = {
            'heads': sum(1 for k, _, _ in nodes if k == 'head'),
            'tables': sum(1 for k, _, _ in nodes if k == 'table'),
            'bodys': sum(1 for k, _, _ in nodes if k == 'body'),
            'depth': max([l for k, l, _ in nodes if k == 'head'] or [0]),
            'head_paths': hp,
            'flaws': structure_flaws(nodes, p),
        }
    # 문서 간 헤딩 경로 겹침 (Jaccard) — 통합·중복 후보
    keys = list(docs)
    overlaps = []
    for i in range(len(keys)):
        a = set(docs[keys[i]]['head_paths'])
        if len(a) < 4:
            continue
        for j in range(i + 1, len(keys)):
            b = set(docs[keys[j]]['head_paths'])
            if len(b) < 4:
                continue
            inter = a & b
            if not inter:
                continue
            jac = len(inter) / len(a | b)
            if jac >= 0.30:
                overlaps.append({'a': keys[i], 'b': keys[j],
                                 'jaccard': round(jac, 3), 'shared': len(inter)})
    overlaps.sort(key=lambda x: -x['jaccard'])
    return docs, overlaps


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    target = sys.argv[1]
    a = sys.argv[2:]
    paths_out = report_out = None
    for i, x in enumerate(a):
        if x == '--paths' and i + 1 < len(a): paths_out = a[i + 1]
        if x == '--report' and i + 1 < len(a): report_out = a[i + 1]

    if os.path.isdir(target):
        files = []
        for r, _, fs in os.walk(target):
            for f in fs:
                if f.endswith('.md'):
                    files.append(os.path.join(r, f))
        files.sort()
    else:
        files = [target]

    docs, overlaps = analyze(files)
    flawed = {p: d['flaws'] for p, d in docs.items() if d['flaws']}
    sys.stderr.write(f'[doc_tree_md] 문서 {len(files)} · 구조이상 {len(flawed)} · 겹침쌍 {len(overlaps)}\n')

    if paths_out and len(files) == 1:
        open(paths_out, 'w').write(to_paths(parse_md(files[0])))
        sys.stderr.write(f'  → {paths_out}\n')
    if report_out:
        json.dump({'docs': docs, 'overlaps': overlaps},
                  open(report_out, 'w'), ensure_ascii=False)
        sys.stderr.write(f'  → {report_out}\n')
    if not paths_out and not report_out:
        for p, f in sorted(flawed.items())[:40]:
            print(f'{os.path.basename(p):60} {" · ".join(f)}')


if __name__ == '__main__':
    main()
