#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
회의록 데이터(YAML) → HWPX 회의록 생성기 (+ Markdown 사본)

발주처/RFP 제공 양식(reference/form/회의록-양식.hwpx)을 **스켈레톤으로 그대로 재사용**하고,
그 안의 Contents/section0.xml만 in-place 편집해 내용을 주입한다.
표 병합·열폭·테두리·스타일 ID는 스켈레톤에서 그대로 상속되므로 양식을 최대한 따른다.

편집 대상:
  - 제목 문단 '회의록 (N)'  ← 회차
  - 작성자 문단             ← 작성자
  - 기본사항 표             ← 회의일시 / 회의장소 / 참석자(구분 라벨은 데이터에서, 행 수 가변)
  - 안건내용 표             ← 데이터행 복제 주입(안건/회의내용▪/결정사항/비고)
  - 합의내용 표             ← 데이터행 복제 주입(합의내용/합의전제/비고)

설계 메모:
  - 셀 문단은 스켈레톤의 실제 문단을 deepcopy 해 <hp:t> 텍스트만 교체 → paraPr/charPr 스타일 보존.
  - linesegarray(레이아웃 캐시)는 textpos=0 한 개만 남김 → 한컴이 열 때 재계산(검증 안전).
  - 표에 행을 추가하면 각 셀 cellAddr@rowAddr 재번호 + 표 rowCnt 갱신(필수).
  - 재패키징: mimetype STORED 첫 엔트리, 빈 디렉터리 엔트리 제거, section0.xml만 교체(나머지 원본).
    (ZIP 패키징·자기검증 패턴은 ax-ipnavi-isp-doc/scripts/build_hwpx_native.py 방식을 차용)

사용법:
  python3 minutes_to_hwpx.py <data.yml> [--hwpx out.hwpx] [--md out.md] [--outdir dir] [--skeleton form.hwpx]
  표준 배치: scripts/minutes/tmp/<이름>.yml → scripts/minutes/outputs/<이름>.{hwpx,md} 자동.
  (yml 이 tmp/ 안이면 산출물은 형제 outputs/ 로, 아니면 yml 위치에 생성)
"""
import argparse
import sys
import zipfile
from copy import deepcopy
from pathlib import Path

try:
    from lxml import etree
except ImportError:  # pragma: no cover
    sys.exit("lxml 필요: pip install --user lxml")
try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("PyYAML 필요: pip install --user pyyaml")

HP = "http://www.hancom.co.kr/hwpml/2011/paragraph"


def q(tag):
    return f"{{{HP}}}{tag}"


def ln(el):
    return etree.QName(el).localname


ROOT_DIR = Path(__file__).resolve().parents[2]
DEFAULT_SKELETON = ROOT_DIR / "reference" / "form" / "회의록-양식.hwpx"

SECTION_PATH = "Contents/section0.xml"


# ─────────────────────────── XML 편집 헬퍼 ───────────────────────────

def _first_t_with(el, marker):
    """el 하위에서 marker 를 포함하는 첫 <hp:t> 반환."""
    for t in el.iter(q("t")):
        if t.text and marker in t.text:
            return t
    return None


def set_marker_text(root, marker, new_text):
    """본문 문단 중 marker 를 담은 <hp:t> 의 텍스트를 통째로 교체."""
    t = _first_t_with(root, marker)
    if t is not None:
        t.text = new_text
        return True
    return False


def _direct(el, name):
    return [c for c in el if ln(c) == name]


def _lineseg_metrics(tpl_p):
    """템플릿 문단의 기존 lineseg에서 (font_pt, line_spacing%, horzsize) 추출.

    셀마다 글꼴 크기·줄간격·본문폭이 다르므로(예: 회의내용 폭 25764 vs 안건 폭 8504)
    양식이 이미 담고 있는 값을 그대로 읽어 쓴다.
    """
    lsa = tpl_p.find(q("linesegarray"))
    seg = lsa.find(q("lineseg")) if lsa is not None else None
    if seg is None:
        return 10, 160, 8000  # 안전 기본값
    vertsize = int(seg.get("vertsize", "1000")) or 1000
    spacing = int(seg.get("spacing", "600"))
    horzsize = int(seg.get("horzsize", "8000")) or 8000
    font_pt = max(1, vertsize // 100)
    ls_pct = round(100 + spacing * 100 / vertsize)
    return font_pt, ls_pct, horzsize


def _build_linesegarray(text, font_pt, ls_pct, horzsize, vertpos_offset):
    """텍스트를 horzsize 폭으로 줄 분할해 lineseg를 생성. vertpos는 vertpos_offset부터 누적.

    한 셀 안에 문단이 여러 개면(회의내용 개조식) 문단마다 vertpos_offset을 누적해야
    세로로 겹치지 않는다. (겹침 버그의 근본 원인 = 모든 문단 vertpos=0)
    반환: (linesegarray Element, 이 문단이 차지한 세로 높이)
    OWPML 공식은 ax-ipnavi-isp-doc build_hwpx_native._calc_lineseg 준용.
    """
    vertsize = font_pt * 100
    baseline = int(vertsize * 0.85)
    spacing = int(vertsize * (ls_pct - 100) / 100)
    line_height = vertsize + spacing

    line_starts = [0]
    if text:
        em = font_pt * 100
        cur_w = 0
        for idx, ch in enumerate(text):
            o = ord(ch)
            full = o > 0x2000 and not (0x2018 <= o <= 0x201F)  # CJK·전각=em, ASCII·기호=em/2
            cw = em if full else em // 2
            if cur_w + cw > horzsize and idx > line_starts[-1]:
                line_starts.append(idx)
                cur_w = cw
            else:
                cur_w += cw

    tlen = len(text)
    lsa = etree.Element(q("linesegarray"))
    for i, tp in enumerate(line_starts):
        seg = etree.SubElement(lsa, q("lineseg"))
        seg.set("textpos", str(min(tp, tlen) if tlen else 0))
        seg.set("vertpos", str(vertpos_offset + i * line_height))
        seg.set("vertsize", str(vertsize))
        seg.set("textheight", str(vertsize))
        seg.set("baseline", str(baseline))
        seg.set("spacing", str(spacing))
        seg.set("horzpos", "0")
        seg.set("horzsize", str(horzsize))
        seg.set("flags", "393216")
    return lsa, len(line_starts) * line_height


def _build_cell_para(tpl_p, text, font_pt, ls_pct, horzsize, vertpos_offset):
    """셀 문단 템플릿을 복제해 텍스트를 넣고 linesegarray를 새로 계산. (문단, 세로높이) 반환."""
    p = deepcopy(tpl_p)
    p.attrib.pop("id", None)  # 중복 id 방지(양식 생성기 관례상 생략)
    runs = _direct(p, "run")
    for extra in runs[1:]:
        p.remove(extra)
    run = runs[0]
    t = run.find(q("t"))
    if t is None:
        t = etree.SubElement(run, q("t"))
    t.text = text
    old = p.find(q("linesegarray"))
    if old is not None:
        p.remove(old)
    lsa, height = _build_linesegarray(text, font_pt, ls_pct, horzsize, vertpos_offset)
    p.append(lsa)  # linesegarray 는 run 뒤(문단 마지막 자식)
    return p, height


def set_cell_text(tc, text):
    """단일 문단 셀에 텍스트 주입(폭 초과 시 자동 줄바꿈)."""
    sub = tc.find(q("subList"))
    ps = _direct(sub, "p")
    tpl = deepcopy(ps[0])
    for p in ps:
        sub.remove(p)
    font_pt, ls_pct, horzsize = _lineseg_metrics(tpl)
    p, _ = _build_cell_para(tpl, "" if text is None else str(text), font_pt, ls_pct, horzsize, 0)
    sub.append(p)


def set_cell_bullets(tc, lines, bullet="▪ "):
    """회의내용처럼 여러 줄(개조식) 셀에 bullet 문단 여러 개 주입(vertpos 누적)."""
    sub = tc.find(q("subList"))
    ps = _direct(sub, "p")
    tpl = deepcopy(ps[0])
    for p in ps:
        sub.remove(p)
    font_pt, ls_pct, horzsize = _lineseg_metrics(tpl)
    kept = [str(x) for x in (lines or []) if str(x).strip()]
    if not kept:
        p, _ = _build_cell_para(tpl, "", font_pt, ls_pct, horzsize, 0)
        sub.append(p)
        return
    vpos = 0
    for line in kept:
        p, height = _build_cell_para(tpl, bullet + line, font_pt, ls_pct, horzsize, vpos)
        vpos += height
        sub.append(p)


def cell_by_col(tr, col_addr):
    for c in _direct(tr, "tc"):
        ca = c.find(q("cellAddr"))
        if ca is not None and ca.get("colAddr") == str(col_addr):
            return c
    return None


def _cell_content_height(tc):
    """셀 내용 세로 높이 = 마지막 lineseg vertpos + 줄높이(모든 문단 통틀어 최대)."""
    maxh = 0
    for seg in tc.iter(q("lineseg")):
        vp = int(seg.get("vertpos", "0"))
        vs = int(seg.get("vertsize", "1000"))
        sp = int(seg.get("spacing", "0"))
        maxh = max(maxh, vp + vs + sp)
    return maxh


def fit_row_heights(tbl, spacious=True):
    """데이터행(1×1 셀) 높이를 내용에 맞춘다. 표 총 높이(hp:sz)도 갱신.

    spacious=True  : 양식의 넉넉한 행 높이를 최소값으로 유지하고 내용이 넘치면 키움(안건내용).
    spacious=False : 양식 높이 무시, 내용 높이에 딱 맞춤 → 짧은 내용은 짧게(합의내용, 가변).
    ※ 병합셀이 있는 표(기본사항)에는 호출하지 않는다 — 1×1 표 전용.
    """
    rows = _direct(tbl, "tr")
    total = 0
    for tr in rows:
        cells = _direct(tr, "tc")
        row_h = 0
        for c in cells:
            cs = c.find(q("cellSz"))
            base = int(cs.get("height", "0")) if (spacious and cs is not None) else 0
            cm = c.find(q("cellMargin"))
            mt = int(cm.get("top", "141")) if cm is not None else 141
            mb = int(cm.get("bottom", "141")) if cm is not None else 141
            need = _cell_content_height(c) + mt + mb
            row_h = max(row_h, base, need)
        for c in cells:
            cs = c.find(q("cellSz"))
            if cs is not None:
                cs.set("height", str(row_h))
        total += row_h
    sz = tbl.find(q("sz"))
    if sz is not None:
        sz.set("height", str(total))


def fill_data_table(tbl, records, filler, spacious=True):
    """헤더행(row0)은 유지하고, 데이터행을 records 개수만큼 복제·주입."""
    trs = _direct(tbl, "tr")
    if len(trs) < 2:
        raise ValueError("데이터행 템플릿이 없는 표")
    header, data_rows = trs[0], trs[1:]
    tpl_row = deepcopy(data_rows[0])
    for r in data_rows:
        tbl.remove(r)
    recs = records or []
    if not recs:
        recs = [{}]  # 최소 빈 행 1개 유지(양식 형태 보존)
    for i, rec in enumerate(recs):
        new_row = deepcopy(tpl_row)
        for c in _direct(new_row, "tc"):
            ca = c.find(q("cellAddr"))
            ca.set("rowAddr", str(i + 1))
        filler(new_row, rec)
        tbl.append(new_row)
    tbl.set("rowCnt", str(1 + len(recs)))
    fit_row_heights(tbl, spacious=spacious)


# ─────────────────────────── 표별 filler ───────────────────────────

def _norm_lines(v):
    if v is None:
        return []
    if isinstance(v, (list, tuple)):
        return list(v)
    return [v]


def fill_agenda(tr, rec):  # 안건내용: 안건 | 회의내용 | 결정사항 | 비고
    set_cell_text(cell_by_col(tr, 0), rec.get("안건", ""))
    set_cell_bullets(cell_by_col(tr, 1), _norm_lines(rec.get("회의내용")))
    set_cell_text(cell_by_col(tr, 2), rec.get("결정사항", ""))
    set_cell_text(cell_by_col(tr, 3), rec.get("비고", ""))


def fill_agreement(tr, rec):  # 합의내용: 합의 내용 | 합의 전제 | 비고
    set_cell_text(cell_by_col(tr, 0), rec.get("합의내용", ""))
    set_cell_text(cell_by_col(tr, 1), rec.get("합의전제", ""))
    set_cell_text(cell_by_col(tr, 2), rec.get("비고", ""))


def attendee_items(att):
    """참석자 → [(구분, [명단…])] — 라벨(구분)도 데이터에서 나온다.

    - list(신규): [{구분: 수행기관, 명단: [...]}, …] — 과제별 기관 구성에 맞춰 자유롭게
    - dict(구): {수행기관: [...], …} — 키가 곧 라벨(기존 yml 무수정 호환)
    """
    if isinstance(att, dict):
        return [(str(k), _norm_lines(v)) for k, v in att.items()]
    items = []
    for rec in _norm_lines(att):
        if isinstance(rec, dict):
            items.append((str(rec.get("구분", "") or ""), _norm_lines(rec.get("명단"))))
        else:
            items.append(("", _norm_lines(rec)))
    return items


def _cell_h(tc, default=1765):
    cz = tc.find(q("cellSz"))
    return int(cz.get("height", str(default))) if cz is not None else default


def fill_basic(tbl, data):  # 기본사항
    trs = _direct(tbl, "tr")
    r0, r1, r2 = trs[0], trs[1], trs[2]
    set_cell_text(cell_by_col(r0, 1), data.get("회의일시", ""))
    set_cell_text(cell_by_col(r0, 4), data.get("회의장소", ""))

    items = attendee_items(data.get("참석자")) or [("", [])]
    h0, row_h = _cell_h(cell_by_col(r0, 0)), _cell_h(cell_by_col(r2, 1))

    # 참석자 행을 항목 수만큼 확보(양식은 2행) — 둘째 행(r2)을 복제·삭제해 맞춘다
    tbl.remove(r2)
    rows = [r1] + [deepcopy(r2) for _ in items[1:]]
    for row in rows[1:]:
        tbl.append(row)

    label_cell = cell_by_col(r1, 0)  # '참석자' 세로 병합 셀 — 행 수만큼 병합 확장
    label_cell.find(q("cellSpan")).set("rowSpan", str(len(rows)))
    label_cell.find(q("cellSz")).set("height", str(row_h * len(rows)))

    for i, (row, (구분, 명단)) in enumerate(zip(rows, items)):
        for c in _direct(row, "tc"):
            c.find(q("cellAddr")).set("rowAddr", str(i + 1))
        set_cell_text(cell_by_col(row, 1), f"({구분})" if 구분 else "")
        set_cell_text(cell_by_col(row, 2), ", ".join(명단))

    tbl.set("rowCnt", str(1 + len(rows)))
    sz = tbl.find(q("sz"))
    if sz is not None:
        sz.set("height", str(h0 + row_h * len(rows)))


# ─────────────────────────── 조립·패키징·검증 ───────────────────────────

def _has_table(p):
    return any(ln(e) == "tbl" for e in p.iter())


def _is_blank_para(p):
    if ln(p) != "p" or _has_table(p):
        return False
    return "".join(t.text or "" for t in p.iter(q("t"))).strip() == ""


def ensure_spacers(root):
    """각 표(박스) 문단 뒤에 빈 문단 1개를 넣어 □ 절 사이 가시성을 확보.

    이미 빈 문단이 뒤따르면 건너뛴다(기본사항 뒤 기존 빈 줄 중복 방지).
    """
    blank_tpl = None
    for c in root:
        if _is_blank_para(c):
            blank_tpl = deepcopy(c)
            blank_tpl.attrib.pop("id", None)
            break
    if blank_tpl is None:
        return
    for tp in [c for c in root if ln(c) == "p" and _has_table(c)]:
        nxt = tp.getnext()
        if nxt is None or not _is_blank_para(nxt):
            tp.addnext(deepcopy(blank_tpl))


def insert_subtitle(root, text):
    """제목 문단(첫 문단) 바로 뒤에 부제목 문단 삽입 — 12pt(charPr 13)·가운데(paraPr 21).

    빈 문단을 복제해 네임스페이스를 보존하고, run·linesegarray만 새로 구성한다.
    """
    ps = [c for c in root if ln(c) == "p"]
    if not ps:
        return
    tpl = None
    for c in ps[1:]:
        if _is_blank_para(c):
            tpl = deepcopy(c)
            break
    if tpl is None:
        return
    tpl.attrib.pop("id", None)
    tpl.set("paraPrIDRef", "21")   # 가운데 정렬
    tpl.set("styleIDRef", "21")
    runs = _direct(tpl, "run")
    for extra in runs[1:]:
        tpl.remove(extra)
    run = runs[0]
    run.set("charPrIDRef", "13")   # 12pt(제목 20pt보다 작게)
    t = run.find(q("t"))
    if t is None:
        t = etree.SubElement(run, q("t"))
    t.text = text
    old = tpl.find(q("linesegarray"))
    if old is not None:
        tpl.remove(old)
    lsa, _ = _build_linesegarray(text, 12, 160, 51024, 0)
    tpl.append(lsa)
    ps[0].addnext(tpl)


def build_section(data, skeleton_path):
    with zipfile.ZipFile(skeleton_path) as z:
        sec = z.read(SECTION_PATH)
    root = etree.fromstring(sec)

    # 마커 치환을 먼저, 부제목 삽입을 나중에 — set_marker_text 는 부분문자열·최초 1건 매칭이라
    # 부제목을 먼저 넣으면 '작성자'·'회의록' 이 든 제목이 마커로 오인돼 부제목이 덮어써진다.
    set_marker_text(root, "회의록", "회의록")  # 양식의 '회의록 (1)' → '회의록'
    author = data.get("작성자", "○○○")  # 특정 업체명 하드코딩 금지 — yml 에서 받는다
    set_marker_text(root, "작성자", f"  작성자 : {author}  ")
    subtitle = str(data.get("제목", "") or "").strip()
    if subtitle:
        insert_subtitle(root, subtitle)     # '회의록' 아래 작은 부제목(주제)

    tbls = [e for e in root.iter(q("tbl"))]  # 문서순: 기본사항, 안건내용, 합의내용
    if len(tbls) < 3:
        raise ValueError(f"양식 표 3개 기대, {len(tbls)}개 발견")
    fill_basic(tbls[0], data)
    fill_data_table(tbls[1], data.get("안건내용"), fill_agenda, spacious=True)   # 안건: 넉넉한 높이
    fill_data_table(tbls[2], data.get("합의내용"), fill_agreement, spacious=False)  # 합의: 가변 높이
    ensure_spacers(root)  # □ 절 사이 빈 줄

    return etree.tostring(root, xml_declaration=True, encoding="UTF-8", standalone=True)


def repackage(skeleton_path, section_bytes, out_path):
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = out_path.with_suffix(out_path.suffix + ".tmp")
    with zipfile.ZipFile(skeleton_path) as src:
        names = [n for n in src.namelist() if not n.endswith("/")]
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as dst:
            info = zipfile.ZipInfo("mimetype")
            info.compress_type = zipfile.ZIP_STORED
            dst.writestr(info, src.read("mimetype"))
            for n in names:
                if n == "mimetype":
                    continue
                payload = section_bytes if n == SECTION_PATH else src.read(n)
                dst.writestr(n, payload, zipfile.ZIP_DEFLATED)
    tmp.replace(out_path)


def validate_hwpx(out_path):
    errs = []
    with zipfile.ZipFile(out_path) as z:
        infos = z.infolist()
        if not infos or infos[0].filename != "mimetype" or infos[0].compress_type != zipfile.ZIP_STORED:
            errs.append("mimetype 가 첫 엔트리(STORED)여야 함")
        sroot = etree.fromstring(z.read(SECTION_PATH))
        hroot = etree.fromstring(z.read("Contents/header.xml"))
        n_para = sum(1 for e in hroot.iter() if ln(e) == "paraPr")
        n_char = sum(1 for e in hroot.iter() if ln(e) == "charPr")
        for e in sroot.iter():
            for attr, cnt, label in (("paraPrIDRef", n_para, "paraPr"),
                                     ("charPrIDRef", n_char, "charPr")):
                v = e.get(attr)
                if v is not None and v.isdigit() and int(v) >= cnt:
                    errs.append(f"{label} 참조초과: {v} >= 정의 {cnt}")
        for p in sroot.iter(q("p")):
            chars = sum(len(t.text or "") for t in p.iter(q("t")))
            for seg in p.iter(q("lineseg")):
                tp = int(seg.get("textpos", "0"))
                if tp > chars:
                    errs.append(f"lineseg textpos {tp} > 글자수 {chars}")
    return sorted(set(errs))


# ─────────────────────────── Markdown 사본(git 기록용) ───────────────────────────

def _md_cell(s):
    return str(s if s is not None else "").replace("|", "\\|").replace("\n", "<br>")


def render_md(data):
    제목 = data.get("제목", "")
    items = attendee_items(data.get("참석자"))
    out = []
    out.append("# 회의록" + (f" — {제목}" if 제목 else ""))
    out.append("")
    out.append(f"> 회의 일시 {data.get('회의일시','')} · 회의장소 {data.get('회의장소','')} · 작성자 {data.get('작성자','')}")
    if items:
        out.append("> 참석자 — " + " / ".join(
            (f"({구분}) " if 구분 else "") + ", ".join(명단) for 구분, 명단 in items))
    out.append("")
    out.append("## 안건내용")
    out.append("")
    out.append("| 안건 | 회의내용 | 결정사항 | 비고(향후계획) |")
    out.append("|---|---|---|---|")
    for rec in data.get("안건내용", []) or []:
        content = "<br>".join("▪ " + _md_cell(x) for x in _norm_lines(rec.get("회의내용")))
        out.append(f"| {_md_cell(rec.get('안건',''))} | {content} | {_md_cell(rec.get('결정사항',''))} | {_md_cell(rec.get('비고',''))} |")
    out.append("")
    out.append("## 합의내용")
    out.append("")
    out.append("| 합의 내용 | 합의 전제 | 비고(향후계획) |")
    out.append("|---|---|---|")
    for rec in data.get("합의내용", []) or []:
        out.append(f"| {_md_cell(rec.get('합의내용',''))} | {_md_cell(rec.get('합의전제',''))} | {_md_cell(rec.get('비고',''))} |")
    out.append("")
    return "\n".join(out)


# ─────────────────────────── CLI ───────────────────────────

def resolve_outdir(data_path, outdir_arg):
    """산출물 폴더 결정. yml 이 tmp/ 안이면 형제 outputs/, 아니면 yml 위치.

    표준 배치: scripts/minutes/tmp/*.yml → scripts/minutes/outputs/*.{hwpx,md}
    """
    if outdir_arg:
        return Path(outdir_arg)
    if data_path.parent.name == "tmp":
        return data_path.parent.parent / "outputs"
    return data_path.parent


def main(argv=None):
    ap = argparse.ArgumentParser(description="회의록 데이터(YAML) → HWPX (+ Markdown)")
    ap.add_argument("data", help="회의록 데이터 YAML 경로(권장: scripts/minutes/tmp/ 안)")
    ap.add_argument("--hwpx", help="HWPX 출력 경로(기본: outputs 폴더/같은 이름 .hwpx)")
    ap.add_argument("--md", help="Markdown 출력 경로(기본: outputs 폴더/같은 이름 .md)")
    ap.add_argument("--outdir", help="산출물 폴더(기본: yml 이 tmp/ 안이면 형제 outputs/, 아니면 yml 위치)")
    ap.add_argument("--no-md", action="store_true", help="Markdown 사본 생성 안 함")
    ap.add_argument("--skeleton", default=str(DEFAULT_SKELETON), help="양식 스켈레톤 HWPX 경로")
    a = ap.parse_args(argv)

    data_path = Path(a.data)
    data = yaml.safe_load(data_path.read_text(encoding="utf-8")) or {}
    skeleton = Path(a.skeleton)
    if not skeleton.exists():
        sys.exit(f"스켈레톤 없음: {skeleton}")

    outdir = resolve_outdir(data_path, a.outdir)
    name = data_path.stem
    hwpx_path = Path(a.hwpx) if a.hwpx else outdir / f"{name}.hwpx"

    section = build_section(data, skeleton)
    repackage(skeleton, section, hwpx_path)
    errs = validate_hwpx(hwpx_path)

    n_agenda = len(data.get("안건내용", []) or [])
    n_agree = len(data.get("합의내용", []) or [])
    print(f"[HWPX] {hwpx_path}  (안건 {n_agenda} · 합의 {n_agree})")

    if not a.no_md:
        md_path = Path(a.md) if a.md else outdir / f"{name}.md"
        md_path.parent.mkdir(parents=True, exist_ok=True)
        md_path.write_text(render_md(data), encoding="utf-8")
        print(f"[MD]   {md_path}")

    if errs:
        print("검증 경고:", file=sys.stderr)
        for e in errs:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print("검증 통과 ✓")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
