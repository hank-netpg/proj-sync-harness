#!/usr/bin/env python3
"""문서 트리구조 분해 파서 (hwpx · docx).

평면 텍스트 추출이 아니라 **계층 트리**로 분해한다:
  장(개요1) → 절(개요2) → 항(개요3) → 본문/표

- hwpx: Contents/header.xml 의 hh:style(name="개요 N")로 개요수준 판정,
        Contents/section*.xml 의 hp:p(styleIDRef)·hp:tbl 파싱.
- docx: styles.xml 의 heading 스타일, document.xml 의 w:p(w:pStyle)·w:tbl 파싱.
- 개요 스타일이 없으면 **선두 번호 패턴**(Ⅰ. / 1. / 1.1 / 가. / (1))으로 heading 휴리스틱 보강.

출력:
  --md   들여쓰기 트리 markdown(사람 검토용, 표는 셀 보존)
  --paths 노드 경로 리스트(예: "Ⅴ-2 > [표] r3c2") — diff 키
기본은 둘 다 stdout.

사용:
  python3 scripts/doc_tree.py <파일.hwpx|.docx> [--md OUT.md] [--paths OUT.tsv]
"""
import sys, os, re, zipfile
import xml.etree.ElementTree as ET

# ---------- 공통 ----------
HEADING_PAT = re.compile(
    r'^\s*('
    r'[ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ]+\s*[.\-]'          # Ⅰ. Ⅱ.
    r'|\d+\.\d+(\.\d+)*\s'                  # 1.1  1.1.1
    r'|\d+\s*[.)]\s'                        # 1.  1)
    r'|[가나다라마바사아자차]\s*[.)]\s'      # 가. 나)
    r'|\(\d+\)\s'                            # (1)
    r')'
)

def _clean(s):
    return re.sub(r'\s+', ' ', (s or '')).strip()

# ---------- hwpx ----------
def parse_hwpx(path):
    z = zipfile.ZipFile(path)
    # 1) 스타일 id → name
    hdr_name = next((n for n in z.namelist() if n.lower().endswith('header.xml')), None)
    style_map = {}
    if hdr_name:
        hdr = z.read(hdr_name).decode('utf-8', 'replace')
        for m in re.finditer(r'<hh:style\s+id="(\d+)"[^>]*\bname="([^"]*)"', hdr):
            style_map[m.group(1)] = m.group(2)
    # 2) section*.xml 순서대로
    secs = sorted(n for n in z.namelist()
                  if re.search(r'Contents/section\d+\.xml$', n, re.I))
    nodes = []  # (kind, level, text)  kind: 'head'|'body'|'table'
    for sec in secs:
        raw = z.read(sec).decode('utf-8', 'replace')
        # 네임스페이스 제거해 태그 접근 단순화
        raw_ns = re.sub(r'\bhp:', '', raw)
        raw_ns = re.sub(r'\bhh:', '', raw_ns)
        raw_ns = re.sub(r'\bhc:', '', raw_ns)
        try:
            root = ET.fromstring(raw_ns)
        except ET.ParseError:
            # 선언 중복 등 → 래핑
            root = ET.fromstring('<root>' + re.sub(r'<\?xml[^>]*\?>', '', raw_ns) + '</root>')
        _walk_hwpx(root, style_map, nodes)
    return nodes

def _para_text(p):
    return _clean(''.join(t.text or '' for t in p.iter('t')))

def _outline_level(style_name):
    m = re.match(r'개요\s*(\d+)', style_name or '')
    if m:
        return int(m.group(1))
    return None

def _walk_hwpx(elem, style_map, nodes):
    tag = elem.tag.split('}')[-1]
    if tag == 'p':
        # 표를 문단이 감싸는 경우: 먼저 표 유무 확인
        tbls = [c for c in elem.iter('tbl')]
        sid = elem.get('styleIDRef') or elem.get('styleRef')
        sname = style_map.get(sid, '')
        txt = _para_text(elem)
        lvl = _outline_level(sname)
        if txt:
            if lvl is not None:
                nodes.append(('head', lvl, txt))
            elif HEADING_PAT.match(txt) and len(txt) < 60:
                nodes.append(('head', _heur_level(txt), txt))
            else:
                nodes.append(('body', None, txt))
        for tb in tbls:
            _emit_table(tb, nodes)
        return
    if tag == 'tbl':
        _emit_table(elem, nodes)
        return
    for c in list(elem):
        _walk_hwpx(c, style_map, nodes)

def _emit_table(tbl, nodes):
    rows = []
    for tr in tbl.iter('tr'):
        cells = []
        for tc in tr.iter('tc'):
            cells.append(_clean(''.join(t.text or '' for t in tc.iter('t'))))
        if cells:
            rows.append(cells)
    if rows:
        nodes.append(('table', None, rows))

def _heur_level(txt):
    if re.match(r'^\s*[ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ]+', txt): return 1
    if re.match(r'^\s*\d+\.\d+\.\d+', txt):        return 3
    if re.match(r'^\s*\d+\.\d+', txt):             return 2
    if re.match(r'^\s*\d+\s*[.)]', txt):           return 2
    if re.match(r'^\s*[가나다라마바사아자차]\s*[.)]', txt): return 3
    if re.match(r'^\s*\(\d+\)', txt):              return 4
    return 2

# ---------- docx ----------
def parse_docx(path):
    z = zipfile.ZipFile(path)
    ns = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
    # heading 스타일 id 집합
    heads = {}
    try:
        st = ET.fromstring(z.read('word/styles.xml'))
        for s in st.iter(ns+'style'):
            sid = s.get(ns+'styleId', '')
            nm = ''
            n = s.find(ns+'name')
            if n is not None: nm = n.get(ns+'val', '')
            m = re.search(r'[Hh]eading\s*(\d+)', sid + ' ' + nm)
            if m: heads[sid] = int(m.group(1))
    except KeyError:
        pass
    doc = ET.fromstring(z.read('word/document.xml'))
    body = doc.find(ns+'body')
    nodes = []
    for el in list(body) if body is not None else []:
        t = el.tag.split('}')[-1]
        if t == 'p':
            txt = _clean(''.join(x.text or '' for x in el.iter(ns+'t')))
            sid = ''
            pPr = el.find(ns+'pPr')
            if pPr is not None:
                ps = pPr.find(ns+'pStyle')
                if ps is not None: sid = ps.get(ns+'val', '')
            if not txt:
                continue
            if sid in heads:
                nodes.append(('head', heads[sid], txt))
            elif HEADING_PAT.match(txt) and len(txt) < 60:
                nodes.append(('head', _heur_level(txt), txt))
            else:
                nodes.append(('body', None, txt))
        elif t == 'tbl':
            rows = []
            for tr in el.iter(ns+'tr'):
                cells = [_clean(''.join(x.text or '' for x in tc.iter(ns+'t')))
                         for tc in tr.iter(ns+'tc')]
                if cells: rows.append(cells)
            if rows: nodes.append(('table', None, rows))
    return nodes

# ---------- 출력 ----------
def to_md(nodes):
    out = []
    for kind, lvl, val in nodes:
        if kind == 'head':
            out.append('#' * min(lvl, 6) + ' ' + val)
        elif kind == 'body':
            out.append(val)
        else:  # table
            for r in val:
                out.append('| ' + ' | '.join(r) + ' |')
            out.append('')
    return '\n'.join(out)

def to_paths(nodes):
    """노드 경로 리스트 — heading 스택으로 경로 구성."""
    stack = []  # (level, text)
    lines = []
    tcount = 0
    bcount = 0
    for kind, lvl, val in nodes:
        if kind == 'head':
            while stack and stack[-1][0] >= lvl:
                stack.pop()
            stack.append((lvl, val))
            path = ' > '.join(t for _, t in stack)
            lines.append(path + '\tHEAD')
            bcount = 0; tcount = 0
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

def parse(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == '.hwpx':
        return parse_hwpx(path)
    if ext == '.docx':
        return parse_docx(path)
    raise SystemExit(f'지원하지 않는 형식: {ext} (hwpx·docx만)')

def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = sys.argv[1]
    md_out = paths_out = None
    a = sys.argv[2:]
    for i, x in enumerate(a):
        if x == '--md' and i+1 < len(a): md_out = a[i+1]
        if x == '--paths' and i+1 < len(a): paths_out = a[i+1]
    nodes = parse(path)
    heads = sum(1 for k,_,_ in nodes if k=='head')
    tbls = sum(1 for k,_,_ in nodes if k=='table')
    bodys = sum(1 for k,_,_ in nodes if k=='body')
    sys.stderr.write(f'[doc_tree] {os.path.basename(path)}: heading={heads} table={tbls} body={bodys}\n')
    md = to_md(nodes); paths = to_paths(nodes)
    if md_out:
        open(md_out, 'w').write(md); sys.stderr.write(f'  → {md_out}\n')
    if paths_out:
        open(paths_out, 'w').write(paths); sys.stderr.write(f'  → {paths_out}\n')
    if not md_out and not paths_out:
        print(md)

if __name__ == '__main__':
    main()
